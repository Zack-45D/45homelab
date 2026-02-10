// docs/.vitepress/config.mjs
export default {
  lang: "en-US",
  title: "45Homelab Repository",
  description: "Centralized links and notes",
  base: "/45homelab/",

  cleanUrls: true,

  themeConfig: {
    siteTitle: "45Homelab Repository",

    nav: [
      { text: "Home", link: "/" },
      { text: "Articles", link: "/articles/" }
    ],

    sidebar: [
      {
        text: "Articles",
        items: [
          { text: "Cloud-Init", link: "/articles/cloud-init/" }
        ]
      }
    ],

    outline: "deep",
    search: { provider: "local" },

    socialLinks: [
      // optional — remove if you don't want it
      { icon: "github", link: "https://github.com/Zack-45D/45homelab" }
    ],

    footer: {
      message: "Companion commands, configs, and links.",
      copyright: "© 45Homelab"
    }
  }
};

