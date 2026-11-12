#!/usr/bin/env python3
"""Copies an MLX model folder without its image weights, for the "Better answers" asset pack.

Qwen 3.5 checkpoints include a vision tower the app never uses (MLXLLM's Qwen35 drops `vision_tower*` and
`model.visual*` when it loads). Leaving them out saves about 0.6 GB of download and storage.

Usage: strip_vision_weights.py <model-folder> <output-folder>

Standard library only: safetensors is an 8-byte header length, a JSON header, then raw tensor bytes.
"""
import json
import shutil
import struct
import sys
from pathlib import Path

DROP = ("vision_tower", "model.visual")
# Files the text-only model needs. Image and video preprocessor configs are left out.
KEEP_FILES = {"config.json", "chat_template.jinja", "tokenizer.json", "tokenizer_config.json", "vocab.json",
              "merges.txt", "special_tokens_map.json", "generation_config.json", "README.md"}


def strip(src: Path, dst: Path) -> tuple[int, int]:
    with src.open("rb") as f:
        n = struct.unpack("<Q", f.read(8))[0]
        header = json.loads(f.read(n))
        base = 8 + n
        meta = header.pop("__metadata__", None)
        keep = sorted((k for k in header if not k.startswith(DROP)), key=lambda k: header[k]["data_offsets"][0])
        out, offset = {}, 0
        for k in keep:
            a, b = header[k]["data_offsets"]
            out[k] = {**header[k], "data_offsets": [offset, offset + (b - a)]}
            offset += b - a
        if meta is not None:
            out["__metadata__"] = meta
        blob = json.dumps(out, separators=(",", ":")).encode()
        blob += b" " * (-len(blob) % 8)  # keep tensor data 8-byte aligned
        with dst.open("wb") as g:
            g.write(struct.pack("<Q", len(blob)))
            g.write(blob)
            for k in keep:
                a, b = header[k]["data_offsets"]
                f.seek(base + a)
                left = b - a
                while left:
                    chunk = f.read(min(left, 64 << 20))
                    g.write(chunk)
                    left -= len(chunk)
    return len(header) - len(keep), len(keep)


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    dst.mkdir(parents=True, exist_ok=True)
    dropped = kept = 0
    for p in sorted(src.iterdir()):
        if p.suffix == ".safetensors":
            d, k = strip(p, dst / p.name)
            dropped, kept = dropped + d, kept + k
        elif p.name in KEEP_FILES:
            shutil.copyfile(p, dst / p.name)
    index = src / "model.safetensors.index.json"
    if index.exists():
        data = json.loads(index.read_text())
        data["weight_map"] = {k: v for k, v in data.get("weight_map", {}).items() if not k.startswith(DROP)}
        data.get("metadata", {}).pop("total_size", None)
        (dst / index.name).write_text(json.dumps(data, indent=2))
    if kept == 0:
        sys.exit("No weights kept: is this an MLX model folder?")
    size = sum(p.stat().st_size for p in dst.iterdir())
    print(f"Kept {kept} tensors, dropped {dropped} image tensors; {size / 1e9:.2f} GB in {dst}")


if __name__ == "__main__":
    main()
