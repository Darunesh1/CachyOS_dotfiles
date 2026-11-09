import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const config: Config = {
  title: 'MyArch',
  tagline: 'Modern Hyprland Configuration with Dynamic Theming',
  favicon: 'img/favicon.ico',

  // Set the production url of your site here
  url: 'https://Darunesh1.github.io',
  // Set the /<baseUrl>/ pathname under which your site is served.
  //
  // This MUST match the GitHub repository name, not the local folder name.
  // The working directory here is ~/MyArch but the remote is
  // github.com/Darunesh1/CachyOS_dotfiles, and GitHub Pages serves a project
  // repo at https://<user>.github.io/<repo>/. It was '/MyArch/' until
  // 2026-11-09, so every asset and internal link on the published site
  // resolved to a path that does not exist.
  baseUrl: '/CachyOS_dotfiles/',

  // GitHub pages deployment config.
  // If you aren't using GitHub pages, you don't need these.
  organizationName: 'Darunesh1', // Usually your GitHub org/user name.
  projectName: 'CachyOS_dotfiles', // The repo name, not the local folder name.
  deploymentBranch: 'gh-pages',
  trailingSlash: false,

  onBrokenLinks: 'throw',

  markdown: {
    format: 'mdx',
    mermaid: true,
    preprocessor: ({filePath, fileContent}) => {
      return fileContent;
    },
    mdx1Compat: {
      comments: true,
      admonitions: true,
      headingIds: true,
    },
  },

  // Even if you don't use internationalization, you can use this field to set
  // useful metadata like html lang. For example, if your site is Chinese, you
  // may want to replace "en" with "zh-Hans".
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          routeBasePath: '/', // Serve the docs at the site's root
        },
        blog: false, // Disable the blog plugin
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    // Replace with your project's social card
    image: 'img/docusaurus-social-card.jpg',
    navbar: {
      title: 'MyArch',
      logo: {
        alt: 'MyArch Logo',
        src: 'img/logo.svg',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'tutorialSidebar',
          position: 'left',
          label: 'Documentation',
        },
        {
          href: 'https://github.com/Darunesh1/MyArch',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Docs',
          items: [
            {
              label: 'Introduction',
              to: '/',
            },
            {
              label: 'Installation',
              to: '/installation',
            },
          ],
        },
        {
          title: 'Community',
          items: [
            {
              label: 'GitHub',
              href: 'https://github.com/Darunesh1/MyArch',
            },
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} Darunesh. Built with Docusaurus.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
