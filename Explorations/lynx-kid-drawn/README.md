# Kid-drawn lynx mascot (parked exploration)

An alternative to the pika: a lynx drawn like a 3rd grader made it (wobbly double marker lines,
crayon fill that misses the edges, googly eyes, blue scarf). Shelved in favour of the pika.

- Code: `Sources/Lynx.swift` (`LynxScout`), switched in by `Scout` in `Sources/Scout.swift`.
- Try it: launch with `-mascot lynx`. Debug builds: `-MascotGallery` shows every mood for both mascots.
- Comparison run: `UITests/MascotComparisonTests.swift`, exported with `scripts/export-screenshots.sh`,
  paired with `tools/side_by_side.swift`. Results are in `comparison/` (pika left, lynx right).
- `lynx_kid_drawing.png` is the original one-off drawing, made with `tools/draw_kid_lynx.py`.
