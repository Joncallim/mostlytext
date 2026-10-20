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

Run the tests (no extra dependencies):

```sh
npm test
```

Build the deployable static site:

```sh
npm ci
npm run build
```

The output is written to `dist/`: the prerendered home page (`index.html`), the prerendered roadmap (`roadmap/index.html`), hashed scripts and styles in `assets/`, and the files from `public/`.

## Deployment

The production site is served from Cloudflare’s static Worker deployment for `mostlytext.app`.

1. Build from a clean checkout of the approved commit with `npm ci && npm run build`.
2. Upload the **contents** of `dist/` as static assets to the existing `mostlytext` Worker, keeping its current routes and asset settings. `/roadmap` reaching `/roadmap/` depends on them: production answers it with an HTTP 307 to `/roadmap/` that keeps the query string, which matches Cloudflare's `auto-trailing-slash` HTML handling of `roadmap/index.html`.
3. Confirm the deployment is Ready, then check `/`, `/roadmap`, `/roadmap/`, `/roadmap/?stage=after-1`, a missing page (404), the fonts and images, and a phone-sized view on the public domain.

The repository intentionally does not contain Cloudflare account configuration, tokens, or DNS settings.

## Search and social metadata

The static site includes canonical URLs, crawl directives, Open Graph/Twitter metadata, `robots.txt`, and `sitemap.xml`. `npm run build` prerenders the home page (`dist/index.html`) and the roadmap (`dist/roadmap/index.html`) with React's server renderer (`scripts/prerender.mjs`), so both pages are complete HTML before JavaScript runs; the browser then hydrates them. The older `/#/roadmap` hash links still open the roadmap. Roadmap stages use production's URL form, `/roadmap/?stage=after-1`; unknown stages show To 1.0 (`src/route.ts`). Without JavaScript the pages stay readable: navigation shows as plain links, every Field guide topic is listed, and controls that need scripting are hidden.

## Licence

See [LICENSE](LICENSE).
