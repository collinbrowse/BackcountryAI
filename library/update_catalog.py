"""Updates one pack's article count and sizes in PackCatalog (Sources/LibraryStore.swift).
Usage: update_catalog.py <LibraryStore.swift> <pack-id> <articles> <download-bytes> <unpacked-bytes>
Exits 1 if the pack has no entry."""
import re
import sys

path, pack, articles, download, unpacked = sys.argv[1:]
fmt = lambda n: f"{int(n):_}"
src = open(path).read()
entry = re.compile(r'(LibraryPack\(id: "%s".*?articles: )[\d_]+(.*?downloadBytes: )[\d_]+(,\s*unpackedBytes: )[\d_]+'
                   % re.escape(pack), re.S)
new, n = entry.subn(lambda m: m.group(1) + fmt(articles) + m.group(2) + fmt(download) + m.group(3) + fmt(unpacked), src)
if n != 1:
    sys.exit(1)
open(path, "w").write(new)
