export default {
  title: "45Homelab Repository",
  description: "Centralized links and notes",
  base: "/45homelab/",

  themeConfig: {
    nav: [
      { text: "Home", link: "/" },
      { text: "Articles", link: "/videos/" }
    ],
    sidebar: [
      {
        text: "Articles",
        items: [
          { text: "Cloud-Init", link: "/videos/cloud-init/" }
        ]
      }
    ]
  }
}

