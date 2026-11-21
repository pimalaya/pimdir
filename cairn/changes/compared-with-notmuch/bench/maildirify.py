"""Turn the Enron tree into Maildir folders, copy K of the corpus.

Copy 1 hardlinks the original files. Copy K > 1 rewrites every Message-ID
domain (and the In-Reply-To/References naming it) so the copy is another set
of messages, and suffixes each user directory with ~K.

Flags are drawn from a hash of the relative path, the same for every copy:
5% in new/ (unread), else cur/ with S 75%, R 8%, F 4%.

usage: python3 -I maildirify.py ENRON_MAILDIR OUT K
"""

import hashlib
import os
import sys

src, out, k = sys.argv[1], sys.argv[2], int(sys.argv[3])
needle = b".JavaMail.evans@thyme"
count = 0
for dirpath, dirnames, filenames in os.walk(src):
    dirnames.sort()
    files = sorted(f for f in filenames if os.path.isfile(os.path.join(dirpath, f)))
    if not files:
        continue
    rel = os.path.relpath(dirpath, src).split(os.sep)
    user = rel[0] if k == 1 else f"{rel[0]}~{k}"
    folder = ".".join(rel[1:]) or "root"
    box = os.path.join(out, user, folder)
    for sub in ("cur", "new", "tmp"):
        os.makedirs(os.path.join(box, sub), exist_ok=True)
    for name in files:
        path = os.path.join(dirpath, name)
        key = os.path.relpath(path, src).encode()
        h = int.from_bytes(hashlib.sha256(key).digest()[:8], "big")
        base = f"{count:07d}.{k}.enron"
        if h % 100 < 5:
            dest = os.path.join(box, "new", base)
        else:
            flags = ""
            if (h >> 8) % 100 < 4:
                flags += "F"
            if (h >> 16) % 100 < 8:
                flags += "R"
            if (h >> 24) % 100 < 75:
                flags += "S"
            dest = os.path.join(box, "cur", f"{base}:2,{flags}")
        if k == 1:
            os.link(path, dest)
        else:
            with open(path, "rb") as f:
                data = f.read()
            with open(dest, "wb") as f:
                f.write(data.replace(needle, needle + str(k).encode()))
        count += 1
print(f"copy {k}: {count} messages into {out}")
