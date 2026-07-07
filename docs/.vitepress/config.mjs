// docs/.vitepress/config.mjs
import { readdirSync, statSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

// ---------------------------------------------------------------------------
// Drafts mechanism
//
// Production builds set VITEPRESS_BUILD=true (see package.json scripts).
// In dev (`npm run docs:dev`), anything in docs/_drafts/ is served at
//   /_drafts/<slug>/
// so you can preview unfinished articles locally. In production the
// drafts folder is excluded from the build entirely — nothing in it ever
// ships to the live site.
// ---------------------------------------------------------------------------

const __dirname = dirname(fileURLToPath(import.meta.url));
const draftsDir = join(__dirname, "..", "_drafts");
const isProductionBuild = process.env.VITEPRESS_BUILD === "true";

const srcExclude = ["**/_templates/**"];
if (isProductionBuild) srcExclude.push("**/_drafts/**");

function listDrafts() {
  if (!existsSync(draftsDir)) return [];
  return readdirSync(draftsDir)
    .filter((name) => {
      const p = join(draftsDir, name);
      try {
        return statSync(p).isDirectory() && existsSync(join(p, "index.md"));
      } catch {
        return false;
      }
    })
    .sort((a, b) => a.localeCompare(b, undefined, { sensitivity: "base" }))
    .map((slug) => ({ text: slug, link: `/_drafts/${slug}/` }));
}

const draftsNav = isProductionBuild
  ? []
  : [{ text: "Drafts (local)", link: "/_drafts/" }];

const draftsSidebar = isProductionBuild
  ? {}
  : {
      "/_drafts/": [
        {
          text: "Drafts (local only — excluded from production)",
          items: listDrafts()
        }
      ]
    };

export default {
  lang: "en-US",
  title: "45Homelab Docs",
  description: "Centralized links and notes",
  base: "/",          // ✅ custom domain (docs.45homelab.com)
  cleanUrls: true,

  srcExclude,

  themeConfig: {
    siteTitle: "45Homelab Docs",

    // ✅ Must live at: docs/public/images/45homelab-logo.png
    logo: "/images/45homelab-logo.png",

    nav: [
      { text: "Home", link: "/" },
      { text: "Articles", link: "/articles/" },
      ...draftsNav
    ],

    // Sidebar appears when you're in /articles/.
    // Entries between the managed:articles-sidebar markers are maintained
    // by scripts/publish.sh — keep the marker comments intact.
    sidebar: {
      "/articles/": [
        {
          text: "Articles",
          items: [
            // managed:articles-sidebar:start
            { text: "Cloud-Init", link: "/articles/cloud-init/" },
            { text: "Homepage", link: "/articles/homepage/" },
            { text: "Odysseus", link: "/articles/odysseus/" },
            { text: "Termix", link: "/articles/termix/" },
            // managed:articles-sidebar:end
          ]
        }
      ],
      ...draftsSidebar
    },

    outline: "deep",
    search: { provider: "local" },

    socialLinks: [
      { icon: "github", link: "https://github.com/Zack-45D/45homelab" }
    ],

    footer: {
      message: "Companion commands, configs, and links.",
      copyright: "© 45Homelab"
    }
  }
};