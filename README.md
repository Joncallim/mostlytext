# MostlyText website

Source for [mostlytext.app](https://mostlytext.app/), the public website for MostlyText, a native macOS text and Markdown editor in active prerelease development.

## What belongs here

This repository contains the website only: a Vite + React static site, its brand assets, and website-specific screenshots. Changes published here are source changes; they do not update the live Cloudflare deployment until a separate deployment is approved.

The native macOS application has its own source repository at [Joncallim/macdown_2](https://github.com/Joncallim/macdown_2). The screenshots in `public/images/` are captures of the application’s development build; they are included here solely for the website.

## Local development

Requires Node.js 20.19+ or 22.12+ (the minimum for the pinned Vite 8).

```sh
npm install
npm run dev
```

Build the deployable static site:

```sh
npm run build
```

The output is written to `dist/`.

## Deployment

The production site is served from Cloudflare’s static Worker deployment for `mostlytext.app`.

1. Run `npm run build`.
2. Upload the **contents** of `dist/` as static assets to the existing `mostlytext` Worker.
3. Confirm the deployment is Ready and verify the public domain.

The repository intentionally does not contain Cloudflare account configuration, tokens, or DNS settings.

## Search and social metadata

The static site includes canonical URLs, crawl directives, Open Graph/Twitter metadata, `robots.txt`, and `sitemap.xml`. `npm run build` prerenders the home page (`dist/index.html`) and the roadmap (`dist/roadmap/index.html`) with React's server renderer (`scripts/prerender.mjs`), so both pages are complete HTML before JavaScript runs; the browser then hydrates them. The older `/#/roadmap` hash links still open the roadmap. Production redirects `/roadmap` to `/roadmap/` before serving assets; keep that behaviour when deploying.

## Licence

See [LICENSE](LICENSE).
