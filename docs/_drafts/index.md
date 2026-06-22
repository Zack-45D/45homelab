# Drafts

This page only exists in **local development**.

The `docs/_drafts/` folder is excluded from production builds (see
`srcExclude` in `docs/.vitepress/config.mjs`), so nothing here is ever
published to the live site.

Use this list to preview unfinished articles. When one is ready, run:

```bash
npm run publish -- <slug> [youtube-url]
```

…which moves the draft into `docs/articles/<slug>/`, prepends the new
entry to the sidebar and indexes, and (optionally) drops in the YouTube
URL. See [docs/_templates/article_workflow.md](../_templates/article_workflow.md)
for the full workflow.
