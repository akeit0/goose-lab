"""Fetch an optional, pinned COLR v0 reference font into the ignored build tree.
No network access occurs during CMake builds. Run this explicitly when desired.
"""
from pathlib import Path
import hashlib
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
URL = "https://github.com/mozilla/twemoji-colr/releases/download/v0.7.0/Twemoji.Mozilla.ttf"
DIGEST = "6d90152ee0d29e82fe2a87793af5aa4b7ad13e6538360889e141e81ed299ee8e"
target = ROOT / "build/fonts/Twemoji.Mozilla.ttf"
data = target.read_bytes() if target.exists() else urllib.request.urlopen(URL, timeout=30).read()
if hashlib.sha256(data).hexdigest() != DIGEST:
    raise ValueError("Unexpected Twemoji Mozilla v0.7.0 font digest")
target.parent.mkdir(parents=True, exist_ok=True)
if not target.exists():
    target.write_bytes(data)
(target.parent / "Twemoji.Mozilla-NOTICE.txt").write_text(
    "Twemoji Mozilla v0.7.0, unmodified upstream release font.\n"
    "Source: https://github.com/mozilla/twemoji-colr/releases/tag/v0.7.0\n"
    "Font-generation code: Copyright Mozilla Foundation, Apache-2.0.\n"
    "Emoji artwork: Twemoji contributors, CC BY 4.0.\n"
    "https://github.com/mozilla/twemoji-colr/blob/master/LICENSE.md\n"
    "https://creativecommons.org/licenses/by/4.0/\n",
    encoding="utf-8")
print(target.as_posix())
