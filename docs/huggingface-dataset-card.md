---
license: cc-by-sa-4.0
language: [en]
pretty_name: Backcountry offline library
tags: [first-aid, survival, wilderness, offline, search]
---

# Backcountry offline library

The text library behind the Backcountry iPhone app: first aid, survival, weather and repair articles,
indexed for offline search.

## Files

- `index.sqlite`: SQLite with an FTS5 index over ~1,500-character passages, plus `sources`, `docs`,
  `passages` and `files` tables.
- `text/<source>/NNNN.md`: the article text. Each article's `files.path`, `offset` and `length` in
  `index.sqlite` point into these shards.

## License

Shared under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Some sources are U.S.
government works in the public domain. Every article keeps its source, license and original URL in
`index.sqlite`. If you reuse this text, credit the original sources below and share it under the same license.

## Sources
