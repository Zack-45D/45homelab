#!/usr/bin/env bash
# scripts/set-youtube.sh — set or update the YouTube link on an article.
#
# Usage:
#   ./scripts/set-youtube.sh <slug> "<youtube-url>"
#   npm run set-youtube -- <slug> "<youtube-url>"
#
# Works on a published article (docs/articles/<slug>/) or on a draft
# (docs/_drafts/<slug>/). Looks for the managed block:
#
#     <!-- youtube:url -->
#     ...anything...
#     <!-- youtube:url:end -->
#
# and replaces its contents.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <slug> \"<youtube-url>\"" >&2
  exit 1
fi

slug="$1"
url="$2"

if [[ ! "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "Error: invalid slug: $slug" >&2
  exit 1
fi

candidates=(
  "docs/articles/$slug/index.md"
  "docs/_drafts/$slug/index.md"
)
target=""
for f in "${candidates[@]}"; do
  if [[ -f "$f" ]]; then target="$f"; break; fi
done
if [[ -z "$target" ]]; then
  echo "Error: no article or draft found for slug '$slug'" >&2
  exit 1
fi

title="$(grep -m1 '^# ' "$target" | sed 's/^# //')"
[[ -z "$title" ]] && title="Video"

python3 - "$target" "$url" "$title" <<'PY'
import re, sys, pathlib
path, url, title = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(path)
src = p.read_text()
start = "<!-- youtube:url -->"
end   = "<!-- youtube:url:end -->"
m = re.search(rf"({re.escape(start)})(.*?)({re.escape(end)})", src, re.S)
if not m:
    sys.exit(f"Error: youtube markers not found in {path}")
body = f"\n- [45Homelab {title} Video]({url})\n"
src = src[:m.start(2)] + body + src[m.end(2):]
p.write_text(src)
print(f"Updated YouTube link in {path}")
PY
