"""Shared plumbing for the scripts that call Claude: the answer grader (grade.py) and the training-data writers in
tools/train-answers. Runs many small requests at once, asks for JSON that matches a schema, keeps a running token
and dollar count, and has a fake client for --dry-run that builds every request but never touches the network.

Two ways to reach Claude, chosen by `backend()`:
- "api": the Anthropic API with ANTHROPIC_API_KEY, billed per token. Needs the `anthropic` package
  (tools/requirements.txt).
- "cli": the Claude Code CLI (`claude -p`) signed in with a Claude subscription, as fastlane/testflight_notes.rb
  does. No API key and no per-token bill; it draws on the subscription's usage limits instead.
With no CLAUDE_BACKEND set, the API is used when ANTHROPIC_API_KEY is there and the CLI otherwise.
--dry-run uses neither, only the standard library.
"""
from __future__ import annotations

import asyncio
import hashlib
import json
import os
import shutil
import sys
import tempfile
import time
from types import SimpleNamespace

# Opus-class by default: used for judging and for writing reference answers. SCOUT_CLAUDE_MODEL picks another
# (for example claude-sonnet-5-5 for a cheaper pass while iterating); compare runs graded by the same model only.
MODEL = os.environ.get("SCOUT_CLAUDE_MODEL", "claude-opus-5-5")
# Dollars per million tokens for MODEL (from the claude-api skill, 2026-11): input, output, cache write (5-minute
# TTL, 1.25x input) and cache read. Only used for the spend line the scripts print at the end.
PRICES = {"input": 4.00, "output": 20.00, "cache_write": 5.00, "cache_read": 0.20}
# Server-side fallback: if Opus's safety classifiers decline a request (rare for first aid, but the questions are
# about bleeding, poisoning and guns sometimes), the API re-runs it on the model Anthropic recommends instead of
# returning a refusal.
FALLBACK_BETA = "server-side-fallback-2026-07-01"


class Spend:
    """Adds up token usage across requests."""

    def __init__(self):
        self.input = self.output = self.cache_write = self.cache_read = self.requests = self.failed = 0
        self.listed = 0.0        # what the CLI says the requests would cost at list prices
        self.subscription = False

    def add(self, usage):
        self.requests += 1
        self.input += getattr(usage, "input_tokens", 0) or 0
        self.output += getattr(usage, "output_tokens", 0) or 0
        self.cache_write += getattr(usage, "cache_creation_input_tokens", 0) or 0
        self.cache_read += getattr(usage, "cache_read_input_tokens", 0) or 0
        cost = getattr(usage, "list_cost_usd", None)
        if cost is not None:
            self.subscription = True
            self.listed += cost

    def dollars(self) -> float:
        """What the requests cost at API prices. On the subscription nothing is billed per token; the figure
        then says what the same run would cost through the API."""
        if self.subscription:
            return self.listed
        return (self.input * PRICES["input"] + self.output * PRICES["output"]
                + self.cache_write * PRICES["cache_write"] + self.cache_read * PRICES["cache_read"]) / 1e6

    def line(self) -> str:
        cost = (f"on the Claude subscription (about ${self.dollars():.2f} at API prices)" if self.subscription
                else f"${self.dollars():.2f}")
        return (f"{self.requests} requests ({self.failed} failed): {self.input:,} input, {self.cache_write:,} cache-write, "
                f"{self.cache_read:,} cache-read, {self.output:,} output tokens = {cost}")

    def as_dict(self) -> dict:
        return {"requests": self.requests, "failed": self.failed, "input_tokens": self.input,
                "cache_write_tokens": self.cache_write, "cache_read_tokens": self.cache_read,
                "output_tokens": self.output, "dollars": round(self.dollars(), 4),
                "billed": "subscription" if self.subscription else "api"}


class FakeClient:
    """Stands in for anthropic.AsyncAnthropic in --dry-run. `fake(kwargs)` returns the text the model would have
    written; everything else (request building, parsing, reports) runs for real."""

    def __init__(self, fake):
        self.fake = fake
        self.last_request = None
        self.beta = SimpleNamespace(messages=SimpleNamespace(create=self._create))

    async def _create(self, **kwargs):
        self.last_request = kwargs
        json.dumps(kwargs)  # the request must be plain JSON, as it would be on the wire
        await asyncio.sleep(0)
        text = self.fake(kwargs)
        size = len(json.dumps(kwargs["messages"])) // 4
        usage = SimpleNamespace(input_tokens=size, output_tokens=len(text) // 4 + 600,
                                cache_creation_input_tokens=0, cache_read_input_tokens=1500)
        return SimpleNamespace(content=[SimpleNamespace(type="text", text=text)], stop_reason="end_turn",
                               usage=usage, model=MODEL)


class CLIClient:
    """Stands in for anthropic.AsyncAnthropic by running each request through the Claude Code CLI (`claude -p`),
    signed in with a Claude subscription or CLAUDE_CODE_OAUTH_TOKEN. Each request is one fresh, tool-less session
    started outside the repository, so Claude sees only the system prompt and the text it is given."""

    def __init__(self, retries: int = 4, timeout: int = 600):
        self.retries, self.timeout = retries, timeout
        self.cwd = tempfile.mkdtemp(prefix="scout-claude-")  # no CLAUDE.md, settings or project files to pick up
        self.last_request = None
        self.beta = SimpleNamespace(messages=SimpleNamespace(create=self._create))

    async def _create(self, **kwargs):
        self.last_request = kwargs
        content = kwargs["messages"][0]["content"]
        text = content if isinstance(content, str) else "\n\n".join(b["text"] for b in content)
        system = "\n\n".join(b["text"] for b in kwargs["system"])
        config = kwargs.get("output_config") or {}
        schema = (config.get("format") or {}).get("schema")
        command = ["claude", "-p", "--model", kwargs["model"], "--effort", config.get("effort", "medium"),
                   "--tools", "", "--system-prompt", system, "--setting-sources", "", "--strict-mcp-config",
                   "--no-session-persistence", "--output-format", "json"]
        if schema is not None:
            command += ["--json-schema", json.dumps(schema)]
        problem = "no reply"
        for attempt in range(self.retries + 1):
            if attempt:
                await asyncio.sleep(min(60, 5 * 2 ** (attempt - 1)))  # usage limits and overloads pass with time
            proc = await asyncio.create_subprocess_exec(
                *command, cwd=self.cwd, stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE)
            try:
                out, err = await asyncio.wait_for(proc.communicate(text.encode()), self.timeout)
            except asyncio.TimeoutError:
                proc.kill()
                problem = f"no reply in {self.timeout} s"
                continue
            try:
                reply = json.loads(out)
            except ValueError:
                problem = (err or out).decode("utf-8", "replace").strip()[:300] or f"exit {proc.returncode}"
                continue
            if reply.get("is_error") or reply.get("subtype") != "success":
                problem = str(reply.get("result") or reply.get("subtype"))[:300]
                continue
            answer = reply.get("structured_output") if schema is not None else None
            body = json.dumps(answer) if answer is not None else (reply.get("result") or "")
            u = reply.get("usage") or {}
            usage = SimpleNamespace(input_tokens=u.get("input_tokens", 0), output_tokens=u.get("output_tokens", 0),
                                    cache_creation_input_tokens=u.get("cache_creation_input_tokens", 0),
                                    cache_read_input_tokens=u.get("cache_read_input_tokens", 0),
                                    list_cost_usd=reply.get("total_cost_usd") or 0.0)
            refused = reply.get("stop_reason") == "refusal" or not body.strip()
            return SimpleNamespace(content=[SimpleNamespace(type="text", text=body)],
                                   stop_reason="refusal" if refused else "end_turn", usage=usage, model=kwargs["model"])
        raise RuntimeError(f"claude -p failed after {self.retries + 1} tries: {problem}")


def backend() -> str:
    """"api" or "cli": CLAUDE_BACKEND if set, else the API when there is a key and the CLI when there isn't."""
    choice = os.environ.get("CLAUDE_BACKEND", "").strip().lower()
    if choice in ("api", "cli"):
        return choice
    if choice:
        sys.exit(f"CLAUDE_BACKEND is {choice!r}; use api or cli.")
    return "api" if os.environ.get("ANTHROPIC_API_KEY") else "cli"


def make_client(dry_run: bool, fake=None, retries: int = 6):
    if dry_run:
        return FakeClient(fake)
    if backend() == "cli":
        if not shutil.which("claude"):
            sys.exit("No ANTHROPIC_API_KEY, and the Claude Code CLI isn't installed. Set the key, or install the CLI "
                     "and sign in with `claude` (it then runs on your Claude subscription).")
        print(f"Using the Claude Code CLI on your Claude subscription ({MODEL}); set ANTHROPIC_API_KEY or "
              "CLAUDE_BACKEND=api to use the API instead.", flush=True)
        return CLIClient()
    try:
        import anthropic
    except ImportError:
        sys.exit("The anthropic package isn't installed: .venv/bin/pip install -r tools/requirements.txt")
    # Credentials come from ANTHROPIC_API_KEY (or an `ant auth login` profile). The SDK retries 429s and 5xx itself.
    return anthropic.AsyncAnthropic(max_retries=retries, timeout=600)


def cached(text: str) -> dict:
    """A text block marked as the end of a cacheable prefix (the rubric, the app's instructions)."""
    return {"type": "text", "text": text, "cache_control": {"type": "ephemeral"}}


async def ask(client, spend: Spend, *, system: list, content: list, schema: dict | None = None,
              effort: str = "medium", max_tokens: int = 16000) -> str:
    """One request. Returns the reply text (JSON when `schema` is given). Raises RuntimeError on a refusal or a
    reply cut off at max_tokens, so the caller can count it as failed instead of using half an answer."""
    kwargs = {
        "model": MODEL,
        "max_tokens": max_tokens,
        "system": system,
        "messages": [{"role": "user", "content": content}],
        # Opus 5.5 always thinks (adaptively); effort is the only dial. Its default is medium.
        "output_config": {"effort": effort},
        "betas": [FALLBACK_BETA],
        "fallbacks": "default",
    }
    if schema is not None:
        kwargs["output_config"]["format"] = {"type": "json_schema", "schema": schema}
    r = await client.beta.messages.create(**kwargs)
    spend.add(r.usage)
    if r.stop_reason == "refusal":
        raise RuntimeError("declined by the model's safety classifier (after any fallback)")
    if r.stop_reason == "max_tokens":
        raise RuntimeError("reply cut off at max_tokens")
    return "".join(b.text for b in r.content if b.type == "text").strip()


async def run_all(items: list, work, concurrency: int, label: str) -> list:
    """Runs `await work(item)` for every item, `concurrency` at a time, printing progress. Returns results in input
    order; a failed item's result is the exception (so one bad request doesn't sink a 1,500-item run)."""
    sem = asyncio.Semaphore(concurrency)
    done = 0
    start = time.time()

    async def one(item):
        nonlocal done
        async with sem:
            try:
                result = await work(item)
            except Exception as e:  # noqa: BLE001 - reported and counted, never silently dropped
                result = e
                print(f"  {label}: failed: {type(e).__name__}: {e}", file=sys.stderr, flush=True)
            done += 1
            if done % 10 == 0 or done == len(items):
                print(f"  {label}: {done}/{len(items)} ({time.time() - start:.0f}s)", flush=True)
            return result

    return await asyncio.gather(*(one(i) for i in items))


def key(*parts) -> str:
    """A short stable id for a piece of work, so reruns can skip what's already done."""
    return hashlib.sha256(json.dumps(parts, sort_keys=True).encode()).hexdigest()[:16]


def load_jsonl(path) -> list:
    try:
        with open(path) as f:
            return [json.loads(line) for line in f if line.strip()]
    except FileNotFoundError:
        return []
