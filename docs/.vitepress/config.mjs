// docs/.vitepress/config.mjs
export default {
  lang: "en-US",
  title: "45Homelab Docs",
  description: "Centralized links and notes",
  base: "/45homelab/",
  cleanUrls: true,

  // ✅ Don't treat docs/_templates as site pages (prevents build failures)
  srcExclude: ["**/_templates/**"],

  themeConfig: {
    siteTitle: "45Homelab Docs",
    logo: "/images/45homelab-logo.png",

    nav: [
      { text: "Home", link: "/" },
      { text: "Articles", link: "/articles/" }
    ],

    // Sidebar only appears when you're in /articles/
    sidebar: {
      "/articles/": [
        {
          text: "Articles",
          items: [
            { text: "Cloud-Init", link: "/articles/cloud-init/" }
            // Add new articles here:
            // { text: "HL15 Beast Deploy", link: "/articles/hl15-beast-deploy/" }
          ]
        }
      ]
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