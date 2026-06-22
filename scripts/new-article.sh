#!/usr/bin/env bash
# scripts/new-article.sh — scaffold a new draft article.
#
# Usage:
#   ./scripts/new-article.sh <slug> "<Article Title>"
#   npm run new -- <slug> "<Article Title>"
#
# Creates:
#   docs/_drafts/<slug>/index.md         (page skeleton)
#   docs/public/files/<slug>/            (downloads folder, with .gitkeep)
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <slug> \"<Article Title>\"" >&2
  exit 1
fi

slug="$1"
title="$2"

if [[ ! "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "Error: slug must be lowercase letters, digits, and hyphens only (got: $slug)" >&2
  exit 1
fi

draft_dir="docs/_drafts/$slug"
public_dir="docs/public/files/$slug"
article_dir="docs/articles/$slug"

if [[ -e "$draft_dir" ]]; then
  echo "Error: $draft_dir already exists" >&2
  exit 1
fi
if [[ -e "$article_dir" ]]; then
  echo "Error: $article_dir already exists (already published?)" >&2
  exit 1
fi

mkdir -p "$draft_dir" "$public_dir"

cat > "$draft_dir/index.md" <<EOF
# $title

## YouTube Video

<!-- youtube:url -->
- [45Homelab $title Video](https://www.youtube.com/watch?...)
<!-- youtube:url:end -->

---

## What this page contains

Notes, commands, and downloadable example files used in the **$title** video.

---

## Notes / Walkthrough

### Step 1 — Section Title

Explanation of what happens here.

---

### Step 2 — Section Title

Explanation of what happens here.

---

## Commands

\`\`\`bash
# example command
docker compose up -d
\`\`\`

---

## Configuration Example

\`\`\`yaml
version: "3.9"
services:
  example:
    image: example:latest
\`\`\`

---

## Example Images

Place images inside:

\`\`\`
docs/public/files/$slug/images/
\`\`\`

Reference them like:

\`\`\`md
![Description](/files/$slug/images/example-1.png)
\`\`\`

---

## Files

- All downloadable files live in \`docs/public/files/$slug/\`.
- Served at: \`/files/$slug/<filename>\`.

---

## References

-
EOF

# Keep the public files folder tracked even when empty.
if [[ ! -e "$public_dir/.gitkeep" ]] && [[ -z "$(ls -A "$public_dir" 2>/dev/null || true)" ]]; then
  touch "$public_dir/.gitkeep"
fi

cat <<EOF
Created draft:
  $draft_dir/index.md
  $public_dir/

Preview locally:
  npm run docs:dev
  → http://127.0.0.1:5173/_drafts/$slug/

When ready to publish:
  npm run publish -- $slug ["https://youtu.be/..."]
EOF
