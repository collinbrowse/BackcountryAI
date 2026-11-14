"""Shared plumbing for the scripts that call Claude: the answer grader (grade.py) and the training-data writers in
tools/train-answers. Runs many small requests at once, asks for JSON that matches a schema, keeps a running token
and dollar count, and has a fake client for --dry-run that builds every request but never touches the network.

Needs the `anthropic` package (tools/requirements.txt) only for live runs; --dry-run uses the standard library.
"""
from __future__ import annotations

import asyncio
import hashlib
import json
import sys
import time
from types import SimpleNamespace

MODEL = "claude-opus-5-5"   # Opus-class: used for judging and for writing reference answers
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

    def add(self, usage):
        self.requests += 1
        self.input += getattr(usage, "input_tokens", 0) or 0
        self.output += getattr(usage, "output_tokens", 0) or 0
        self.cache_write += getattr(usage, "cache_creation_input_tokens", 0) or 0
        self.cache_read += getattr(usage, "cache_read_input_tokens", 0) or 0

    def dollars(self) -> float:
        return (self.input * PRICES["input"] + self.output * PRICES["output"]
                + self.cache_write * PRICES["cache_write"] + self.cache_read * PRICES["cache_read"]) / 1e6

    def line(self) -> str:
        return (f"{self.requests} requests ({self.failed} failed): {self.input:,} input, {self.cache_write:,} cache-write, "
                f"{self.cache_read:,} cache-read, {self.output:,} output tokens = ${self.dollars():.2f}")

    def as_dict(self) -> dict:
        return {"requests": self.requests, "failed": self.failed, "input_tokens": self.input,
                "cache_write_tokens": self.cache_write, "cache_read_tokens": self.cache_read,
                "output_tokens": self.output, "dollars": round(self.dollars(), 4)}


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


def make_client(dry_run: bool, fake=None, retries: int = 6):
    if dry_run:
        return FakeClient(fake)
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
