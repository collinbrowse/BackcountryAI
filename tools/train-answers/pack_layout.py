"""Lays out a fused fine-tuned model like the Hugging Face download scripts/release-model-pack.sh starts from, so
`scripts/release-model-pack.sh --model-dir <out>` packages it exactly like the stock model.

Takes the fused weights from mlx_lm.fuse and everything else (config.json, tokenizer, chat template) from the
pinned base snapshot: mlx_lm.fuse rewrites config.json without vision_config and re-saves the tokenizer, and the
app should see the same files it was tested with. First checks that the fused weights have exactly the base
model's text tensors (same names, shapes and dtypes), which is what the app's MLXLLM Qwen35 loader expects.

Usage: python3 -I tools/train-answers/pack_layout.py <fused-dir> <base-snapshot-dir> <out-dir>
       python3 -I tools/train-answers/pack_layout.py --self-test     (fake tiny safetensors, for --dry-run)
Standard library only.
"""
import json
import shutil
import struct
import sys
import tempfile
from pathlib import Path

DROP = ("vision_tower", "model.visual")   # as tools/strip_vision_weights.py
BASE_FILES = ["config.json", "chat_template.jinja", "tokenizer.json", "tokenizer_config.json", "vocab.json"]
NOTE = """

## Scout fine-tune

This copy was fine-tuned with LoRA (mlx-lm) on reference answers for the Scout field-guide app and fused into the
4-bit weights; the image weights were removed. Base: the model described above, at the pinned revision.
"""


def header(path: Path) -> dict:
    with path.open("rb") as f:
        n = struct.unpack("<Q", f.read(8))[0]
        h = json.loads(f.read(n))
    h.pop("__metadata__", None)
    return h


def tensors(folder: Path) -> dict:
    out = {}
    for p in sorted(folder.glob("*.safetensors")):
        for k, v in header(p).items():
            out[k] = (v["dtype"], tuple(v["shape"]))
    return out


def compare(fused: Path, base: Path) -> list:
    want = {k: v for k, v in tensors(base).items() if not k.startswith(DROP)}
    got = tensors(fused)
    errors = [f"missing {k}" for k in sorted(set(want) - set(got))][:10]
    errors += [f"unexpected {k}" for k in sorted(set(got) - set(want))][:10]
    errors += [f"{k}: {got[k]} vs base {want[k]}" for k in sorted(set(want) & set(got)) if got[k] != want[k]][:10]
    return errors


def layout(fused: Path, base: Path, out: Path) -> None:
    if errors := compare(fused, base):
        sys.exit("Fused weights don't match the base model's text tensors:\n  " + "\n  ".join(errors))
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    for name in BASE_FILES:
        if (base / name).exists():
            shutil.copyfile(base / name, out / name)
    readme = (base / "README.md").read_text() if (base / "README.md").exists() else ""
    (out / "README.md").write_text(readme + NOTE)  # Apache 2.0 asks modified files to say they were changed
    shards = sorted(fused.glob("*.safetensors"))
    for p in shards:
        shutil.copyfile(p, out / p.name)
    index = {"metadata": {}, "weight_map": {k: p.name for p in shards for k in header(p)}}
    (out / "model.safetensors.index.json").write_text(json.dumps(index, indent=2))
    n = len(tensors(out))
    print(f"Laid out {n} tensors in {len(shards)} file(s) with the base model's config and tokenizer in {out}")


def write_fake(path: Path, names: dict) -> None:
    h, offset = {}, 0
    for k, (dtype, shape) in names.items():
        size = 2 * max(1, shape[0] * shape[1])
        h[k] = {"dtype": dtype, "shape": list(shape), "data_offsets": [offset, offset + size]}
        offset += size
    blob = json.dumps(h).encode()
    path.write_bytes(struct.pack("<Q", len(blob)) + blob + b"\0" * offset)


def self_test() -> None:
    text = {"language_model.model.layers.0.mlp.up_proj.weight": ("U32", (8, 4)),
            "language_model.model.layers.0.mlp.up_proj.scales": ("BF16", (8, 1))}
    with tempfile.TemporaryDirectory() as tmp:
        base, fused, out = Path(tmp, "base"), Path(tmp, "fused"), Path(tmp, "out")
        base.mkdir(), fused.mkdir()
        write_fake(base / "model.safetensors", {**text, "vision_tower.blocks.0.weight": ("BF16", (4, 4))})
        for name in BASE_FILES + ["README.md"]:
            (base / name).write_text("{}")
        write_fake(fused / "model.safetensors", text)
        layout(fused, base, out)
        assert set(tensors(out)) == set(text) and (out / "config.json").exists()
        write_fake(fused / "model.safetensors", {**text, "language_model.model.layers.0.mlp.up_proj.scales":
                                                 ("F32", (8, 1))})
        assert compare(fused, base), "a dtype change should be caught"
    print("pack_layout self-test: OK")


def main():
    if sys.argv[1:] == ["--self-test"]:
        return self_test()
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    layout(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]))


if __name__ == "__main__":
    main()
