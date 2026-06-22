#!/usr/bin/env bash
# scripts/publish.sh — promote a draft to a published article.
#
# Usage:
#   ./scripts/publish.sh <slug> [youtube-url]
#   npm run publish -- <slug> [youtube-url]
#
# Effects:
#   - Moves   docs/_drafts/<slug>/   →  docs/articles/<slug>/
#   - Inserts the slug into the sidebar (config.mjs, alphabetical, kept tidy)
#   - Prepends the entry to docs/articles/index.md "All Articles"
#   - Replaces the "Latest" entry in docs/articles/index.md
#   - Prepends to docs/index.md and caps to the 10 most-recent
#   - If a youtube-url is given, substitutes it into the article
#
# Title is read from the article's first H1.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

HOME_CAP=10  # how many entries to keep on the site home

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <slug> [youtube-url]" >&2
  exit 1
fi

slug="$1"
youtube_url="${2:-}"

if [[ ! "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "Error: invalid slug: $slug" >&2
  exit 1
fi

draft_dir="docs/_drafts/$slug"
article_dir="docs/articles/$slug"
draft_md="$draft_dir/index.md"

if [[ ! -f "$draft_md" ]]; then
  echo "Error: no draft at $draft_md" >&2
  exit 1
fi
if [[ -e "$article_dir" ]]; then
  echo "Error: $article_dir already exists" >&2
  exit 1
fi

# Read the title from the draft's first "# " line.
title="$(grep -m1 '^# ' "$draft_md" | sed 's/^# //')"
if [[ -z "$title" ]]; then
  echo "Error: could not find a top-level '# Title' in $draft_md" >&2
  exit 1
fi

echo "Publishing draft '$slug' as: $title"

# Move the draft to the articles tree. Prefer git mv if tracked.
if git ls-files --error-unmatch "$draft_dir" >/dev/null 2>&1; then
  mkdir -p "$(dirname "$article_dir")"
  git mv "$draft_dir" "$article_dir"
else
  mv "$draft_dir" "$article_dir"
fi

# If a YouTube URL was supplied, drop it into the managed block.
if [[ -n "$youtube_url" ]]; then
  ./scripts/set-youtube.sh "$slug" "$youtube_url"
fi

article_link="/articles/$slug/"
article_bullet="- [$title]($article_link)"
sidebar_line="            { text: \"$title\", link: \"$article_link\" },"

# ---- update sidebar in config.mjs (kept sorted, deduped) -----------------
python3 - "$slug" "$title" <<'PY'
import re, sys, pathlib
slug, title = sys.argv[1], sys.argv[2]
cfg = pathlib.Path("docs/.vitepress/config.mjs")
src = cfg.read_text()
start = "// managed:articles-sidebar:start"
end   = "// managed:articles-sidebar:end"
m = re.search(rf"({re.escape(start)})(.*?)({re.escape(end)})", src, re.S)
if not m:
    sys.exit("sidebar markers not found in config.mjs")
block = m.group(2)
lines = [ln for ln in block.splitlines() if ln.strip().startswith("{")]
entry_re = re.compile(r'\{\s*text:\s*"(?P<text>[^"]+)",\s*link:\s*"(?P<link>[^"]+)"\s*\},?')
entries = []
for ln in lines:
    em = entry_re.search(ln)
    if em:
        entries.append((em.group("text"), em.group("link")))
new_link = f"/articles/{slug}/"
entries = [e for e in entries if e[1] != new_link]
entries.append((title, new_link))
entries.sort(key=lambda e: e[0].lower())
indent = "            "
rendered = "\n" + "\n".join(
    f'{indent}{{ text: "{t}", link: "{l}" }},' for (t, l) in entries
) + "\n            "
new_src = src[:m.start(2)] + rendered + src[m.end(2):]
cfg.write_text(new_src)
PY

# ---- update Articles index ----------------------------------------------
python3 - "$slug" "$title" <<'PY'
import re, sys, pathlib
slug, title = sys.argv[1], sys.argv[2]
p = pathlib.Path("docs/articles/index.md")
src = p.read_text()
bullet = f"- [{title}](/articles/{slug}/)"

def replace_block(text, name, body):
    s = f"<!-- managed:{name}:start -->"
    e = f"<!-- managed:{name}:end -->"
    m = re.search(rf"({re.escape(s)})(.*?)({re.escape(e)})", text, re.S)
    if not m:
        sys.exit(f"markers {name} not found in docs/articles/index.md")
    return text[:m.start(2)] + body + text[m.end(2):]

# Latest = just this article.
latest_body = f"\n{bullet}\n"
src = replace_block(src, "latest-article", latest_body)

# All Articles: prepend if not already present, keep sorted alphabetically
m = re.search(r"(<!-- managed:all-articles:start -->)(.*?)(<!-- managed:all-articles:end -->)", src, re.S)
block = m.group(2)
existing = [ln.strip() for ln in block.splitlines() if ln.strip().startswith("- ")]
new_link = f"](/articles/{slug}/)"
existing = [ln for ln in existing if not ln.endswith(new_link)]
existing.append(bullet)
def sort_key(ln):
    t = re.match(r"- \[([^\]]+)\]", ln)
    return (t.group(1).lower() if t else ln.lower())
existing.sort(key=sort_key)
all_body = "\n" + "\n".join(existing) + "\n"
src = replace_block(src, "all-articles", all_body)
p.write_text(src)
PY

# ---- update site home (prepend; cap to HOME_CAP) ------------------------
python3 - "$slug" "$title" "$HOME_CAP" <<'PY'
import re, sys, pathlib
slug, title, cap = sys.argv[1], sys.argv[2], int(sys.argv[3])
p = pathlib.Path("docs/index.md")
src = p.read_text()
bullet = f"- [{title}](/articles/{slug}/)"
s = "<!-- managed:home-articles:start -->"
e = "<!-- managed:home-articles:end -->"
m = re.search(rf"({re.escape(s)})(.*?)({re.escape(e)})", src, re.S)
if not m:
    sys.exit("markers home-articles not found in docs/index.md")
block = m.group(2)
existing = [ln.strip() for ln in block.splitlines() if ln.strip().startswith("- ")]
new_link = f"](/articles/{slug}/)"
existing = [ln for ln in existing if not ln.endswith(new_link)]
existing.insert(0, bullet)        # newest first
existing = existing[:cap]         # keep most-recent N
body = "\n" + "\n".join(existing) + "\n"
src = src[:m.start(2)] + body + src[m.end(2):]
p.write_text(src)
PY

cat <<EOF
Published:
  $article_dir/
  Sidebar entry added (alphabetical).
  Articles index: "Latest" replaced, "All Articles" updated.
  Home index: prepended, capped to $HOME_CAP entries.

Review with:
  git diff --stat
  git diff docs/.vitepress/config.mjs docs/index.md docs/articles/index.md

Preview locally:
  npm run docs:dev    → http://127.0.0.1:5173/articles/$slug/

If you didn't pass a YouTube URL, set it later with:
  npm run set-youtube -- $slug "https://youtu.be/..."
EOF
