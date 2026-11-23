"""`mlx_lm lora` for the Better answers model (Qwen 3.5), with the one change that makes it trainable on a Mac.

24 of the model's 32 layers are Gated DeltaNet layers: a recurrence over the tokens that keeps a 128 x 128 state for
each of 32 heads. mlx-lm runs it with a Metal kernel when generating. The kernel has no gradient, so in training
mlx-lm falls back to its reference code, one Python step per token, and backpropagation then has to keep several
copies of the state for every token of every layer: about 14 GB for one 1,800-token prompt in one layer. A batch of
four of the app's prompts ran out of memory on a 64 GB Mac before the first step finished.

This file swaps that training path for the chunked form of the same recurrence (the one the model was trained with:
`torch_chunk_gated_delta_rule` in transformers' Qwen 3.5 code, from the flash-linear-attention library). Inside a
chunk of 64 tokens the updates collapse into a few matrix products and one triangular system; only the state at
each chunk boundary is kept. Same numbers to float32 rounding, about a fortieth of the memory. Generation and the
validation passes inside training still use mlx-lm's kernel.

Usage: .venv/bin/python -I tools/train-answers/train_lora.py <mlx_lm lora arguments>     (tools/train-answers/train.sh)
       .venv/bin/python -I tools/train-answers/train_lora.py --self-test [MODEL_DIR [train.jsonl]]
The self-test compares outputs and gradients with mlx-lm's reference code on made-up inputs, and with MODEL_DIR the
whole model's output on a real prompt three ways (reference, chunked, kernel). train.sh runs it before training, so
an mlx-lm upgrade that changes the layer fails there and not as a quietly wrong fine-tune.
"""
from __future__ import annotations

import sys

import mlx.core as mx
import mlx.nn as nn
from mlx_lm.models import gated_delta as gd
from mlx_lm.models import qwen3_5

CHUNK = 64  # a power of two (unit_lower_inverse); what the PyTorch reference uses


def unit_lower_inverse(system: mx.array) -> mx.array:
    """The inverses of unit lower-triangular matrices [..., C, C], C a power of two, by halves: the inverse of
    [[A, 0], [B, D]] is [[A', 0], [-D' B A', D']]. Starts from the 1 x 1 blocks on the diagonal and doubles; only
    matrix products, so it runs on the GPU and has a gradient (mx.linalg's triangular solver has neither)."""
    size = system.shape[-1]
    lead = system.shape[:-2]
    inverse = mx.ones((*lead, size, 1, 1), dtype=system.dtype)
    half = 1
    while half < size:
        n = size // (2 * half)
        blocks = system.reshape(*lead, n, 2 * half, n, 2 * half)
        diagonal = mx.moveaxis(mx.diagonal(blocks, axis1=-4, axis2=-2), -1, -3)  # [..., n, 2 half, 2 half]
        below = diagonal[..., half:, :half]
        top, bottom = inverse[..., 0::2, :, :], inverse[..., 1::2, :, :]
        corner = -(bottom @ below @ top)
        inverse = mx.concatenate([mx.concatenate([top, mx.zeros_like(corner)], axis=-1),
                                  mx.concatenate([corner, bottom], axis=-1)], axis=-2)
        half *= 2
    return inverse[..., 0, :, :]


def gated_delta_chunked(q: mx.array, k: mx.array, v: mx.array, log_g: mx.array, beta: mx.array,
                        state: mx.array | None = None, chunk: int = CHUNK) -> tuple[mx.array, mx.array]:
    """The gated delta rule over a whole sequence: for each token, S = g S + beta (v - g S k) k', y = S q.

    q, k: [B, T, Hk, Dk], normalized as `gated_delta.normalize_qk` leaves them. v: [B, T, Hv, Dv].
    log_g (the log of the decay, <= 0) and beta: [B, T, Hv]. state: [B, Hv, Dv, Dk] or None.
    Returns y [B, T, Hv, Dv] in q's type and the last state, as `gated_delta.gated_delta_ops` does."""
    B, T, Hk, Dk = q.shape
    Hv, Dv = v.shape[-2:]
    out_type = q.dtype
    if (repeat := Hv // Hk) > 1:
        q, k = mx.repeat(q, repeat, axis=2), mx.repeat(k, repeat, axis=2)
    q, k, v = (x.astype(mx.float32).transpose(0, 2, 1, 3) for x in (q, k, v))  # [B, Hv, T, D]
    beta, log_g = (x.astype(mx.float32).transpose(0, 2, 1) for x in (beta, log_g))  # [B, Hv, T]
    # Padding with k = v = beta = 0 and no decay changes nothing: the padded tokens write nothing to the state.
    if pad := -T % chunk:
        q, k, v = (mx.pad(x, [(0, 0), (0, 0), (0, pad), (0, 0)]) for x in (q, k, v))
        beta, log_g = (mx.pad(x, [(0, 0), (0, 0), (0, pad)]) for x in (beta, log_g))
    n_chunks = (T + pad) // chunk
    q, k, v = (x.reshape(B, Hv, n_chunks, chunk, x.shape[-1]) for x in (q, k, v))
    beta, log_g = (x.reshape(B, Hv, n_chunks, chunk) for x in (beta, log_g))

    # Inside each chunk. between[t, i] is the decay from token i to token t, for i <= t.
    decay = mx.cumsum(log_g, axis=-1)
    lower = mx.tril(mx.ones((chunk, chunk))) > 0
    between = decay[..., :, None] - decay[..., None, :]
    between = mx.where(lower, mx.exp(mx.where(lower, between, 0)), 0)
    k_beta = k * beta[..., None]
    k_t = k.swapaxes(-1, -2)
    # Token t's update depends on what tokens before it in the chunk wrote: a unit lower-triangular system.
    system = mx.tril((k_beta @ k_t) * between, -1) + mx.eye(chunk)
    inverse = unit_lower_inverse(system)
    from_start = mx.exp(decay)[..., None]
    writes = inverse @ (v * beta[..., None])     # what each token writes if the state coming in were empty
    reads = inverse @ (k_beta * from_start)      # how much of the incoming state each token's write cancels
    within = (q @ k_t) * between                 # how tokens of the chunk read each other's writes
    q = q * from_start
    k_to_end = k * mx.exp(decay[..., -1:] - decay)[..., None]
    chunk_decay = mx.exp(decay[..., -1])[..., None, None]

    # Across chunks, in order. The state here is [B, Hv, Dk, Dv].
    s = mx.zeros((B, Hv, Dk, Dv), dtype=mx.float32) if state is None else state.astype(mx.float32).swapaxes(-1, -2)
    ys = []
    for n in range(n_chunks):
        written = writes[:, :, n] - reads[:, :, n] @ s
        ys.append(q[:, :, n] @ s + within[:, :, n] @ written)
        s = s * chunk_decay[:, :, n] + k_to_end[:, :, n].swapaxes(-1, -2) @ written
    y = mx.concatenate(ys, axis=2)[:, :, :T]
    return y.transpose(0, 2, 1, 3).astype(out_type), s.swapaxes(-1, -2)


_stock_update = gd.gated_delta_update


def gated_delta_update(q, k, v, a, b, A_log, dt_bias, state=None, mask=None, *, use_kernel=True, lower_bound=None,
                       allow_neg_eigval=False):
    """mlx-lm's `gated_delta_update`, with the chunked form wherever it would have looped over tokens."""
    if use_kernel or mask is not None or lower_bound is not None:
        return _stock_update(q, k, v, a, b, A_log, dt_bias, state, mask, use_kernel=use_kernel,
                             lower_bound=lower_bound, allow_neg_eigval=allow_neg_eigval)
    beta = mx.sigmoid(b) * 2.0 if allow_neg_eigval else mx.sigmoid(b)
    log_g = -mx.exp(A_log.astype(mx.float32)) * nn.softplus(a + dt_bias)  # the log of gated_delta.compute_g
    return gated_delta_chunked(q, k, v, log_g, beta, state)


def install():
    qwen3_5.gated_delta_update = gated_delta_update


# MARK: - Self-test

def _made_up(B=2, T=150, Hk=16, Hv=32, D=128, alike=0.0, seed=0):
    """Inputs shaped like the model's. `alike` near 1 makes every key nearly the same vector: the hardest case
    for the triangular system, since each token then cancels most of what the ones before it wrote."""
    mx.random.seed(seed)
    base = mx.random.normal((B, 1, Hk, D))
    q, k = (alike * base + (1 - alike) * mx.random.normal((B, T, Hk, D)) for _ in range(2))
    q, k = gd.normalize_qk(q, k, inv_scale=D**-0.5, eps=1e-6)
    v = mx.random.normal((B, T, Hv, D))
    log_g = -mx.random.uniform(0, 0.3, (B, T, Hv))
    beta = mx.random.uniform(0, 1, (B, T, Hv))
    state = mx.random.normal((B, Hv, D, D)) * 0.1
    return q, k, v, log_g, beta, state


def _worst(a: mx.array, b: mx.array) -> float:
    """The largest difference, as a share of the largest value."""
    return (mx.abs(a - b).max() / mx.maximum(mx.abs(b).max(), 1e-12)).item()


def self_test(model_dir: str | None, data: str | None) -> bool:
    ok = True

    def report(name: str, error: float, limit: float):
        nonlocal ok
        ok = ok and error <= limit
        print(f"  {'ok  ' if error <= limit else 'FAIL'} {name}: {error:.2e} (limit {limit:.0e})")

    print("Chunked recurrence against mlx-lm's reference loop, made-up inputs:")
    for alike in (0.0, 0.9):
        q, k, v, log_g, beta, state = _made_up(alike=alike)
        y0, s0 = gd.gated_delta_ops(q, k, v, mx.exp(log_g), beta, state)
        y1, s1 = gated_delta_chunked(q, k, v, log_g, beta, state)
        report(f"output, keys {'alike' if alike else 'unrelated'}", _worst(y1, y0), 1e-4)
        report(f"last state, keys {'alike' if alike else 'unrelated'}", _worst(s1, s0), 1e-4)

    q, k, v, log_g, beta, state = _made_up(B=1, T=100, alike=0.5, seed=1)
    weights = mx.random.normal((1, 100, 32, 128))

    def loss(fn):
        def f(q, k, v, log_g, beta, state):
            y, s = fn(q, k, v, log_g, beta, state)
            return (y * weights).sum() + (s * s).sum()
        return f

    reference = mx.grad(loss(lambda q, k, v, lg, b, s: gd.gated_delta_ops(q, k, v, mx.exp(lg), b, s)),
                        argnums=[0, 1, 2, 3, 4, 5])(q, k, v, log_g, beta, state)
    chunked = mx.grad(loss(gated_delta_chunked), argnums=[0, 1, 2, 3, 4, 5])(q, k, v, log_g, beta, state)
    for name, g1, g0 in zip(("q", "k", "v", "decay", "beta", "state"), chunked, reference):
        report(f"gradient for {name}", _worst(g1, g0), 1e-3)

    if model_dir:
        import json
        from mlx_lm import load
        print("The whole model on a real prompt (first 400 tokens):")
        model, tokenizer = load(model_dir)
        text = "The quick brown fox jumps over the lazy dog. " * 60
        if data:
            with open(data) as f:
                messages = json.loads(f.readline())["messages"]
            text = tokenizer.apply_chat_template(messages, tokenize=False, enable_thinking=False)
        tokens = mx.array(tokenizer.encode(text)[:400])[None]
        model.eval()
        kernel = model(tokens).astype(mx.float32)
        model.train()
        loop = model(tokens).astype(mx.float32)
        install()
        ours = model(tokens).astype(mx.float32)
        qwen3_5.gated_delta_update = _stock_update
        mx.eval(kernel, loop, ours)
        # Activations between layers are 16-bit, so rounding makes any two code paths drift apart over 32 layers:
        # mlx-lm's own two (its loop and its kernel) differ by about a logit at worst. Ours has to sit inside
        # that spread, and predict the text equally well.
        def apart(a, b):
            return mx.abs(a - b).mean().item()

        def next_token_loss(logits):
            return nn.losses.cross_entropy(logits[0, :-1], tokens[0, 1:]).mean().item()

        def differ(a, b):
            return 1 - (a.argmax(-1) == b.argmax(-1)).astype(mx.float32).mean().item()

        spread = apart(loop, kernel)
        print(f"       mlx-lm's loop against its kernel: mean logit difference {spread:.3f}, "
              f"top prediction differs for {differ(loop, kernel):.1%} of tokens")
        report("mean logit difference, chunked against the loop", apart(ours, loop), 1.5 * spread)
        report("mean logit difference, chunked against the kernel", apart(ours, kernel), 1.5 * spread)
        report("top prediction differs from the kernel's (share of tokens)", differ(ours, kernel),
               differ(loop, kernel) + 0.02)
        losses = [next_token_loss(x) for x in (loop, kernel, ours)]
        print(f"       loss on the text: loop {losses[0]:.4f}, kernel {losses[1]:.4f}, chunked {losses[2]:.4f}")
        report("loss, chunked against the kernel", abs(losses[2] - losses[1]),
               max(0.01, 2 * abs(losses[0] - losses[1])))
    print("Self-test passed" if ok else "Self-test FAILED")
    return ok


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        rest = [a for a in sys.argv[1:] if a != "--self-test"]
        sys.exit(0 if self_test(rest[0] if rest else None, rest[1] if len(rest) > 1 else None) else 1)
    install()
    from mlx_lm import lora
    lora.main()
