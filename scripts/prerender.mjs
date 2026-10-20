// Writes prerendered pages into dist/ after `vite build` and `vite build --ssr`:
// the home page (dist/index.html) and the roadmap (dist/roadmap/index.html).
// The deployable output is still the static dist/ folder.
import fs from "node:fs"
import { pathToFileURL } from "node:url"

const { render } = await import(pathToFileURL("dist-ssr/entry-server.js").href)
const template = fs.readFileSync("dist/index.html", "utf8")

const pages = [
  { file: "dist/index.html", route: "", view: "home", roadmapPage: false, head: {} },
  {
    file: "dist/roadmap/index.html", route: "#/roadmap", view: "#/roadmap", roadmapPage: true,
    head: {
      title: "Roadmap — MostlyText",
      description: "The MostlyText roadmap: current work toward a verified macOS 1.0 release, followed by clearly provisional directions.",
      url: "https://mostlytext.app/roadmap/",
      socialTitle: "MostlyText roadmap",
      socialDescription: "Current work toward a verified macOS 1.0 release, followed by clearly provisional directions.",
    },
  },
]

function replaceOnce(html, pattern, replacement, label) {
  const matches = html.match(new RegExp(pattern.source, pattern.flags.includes("g") ? pattern.flags : pattern.flags + "g"))
  if (!matches || matches.length !== 1) throw new Error(`Expected exactly one ${label} in index.html, found ${matches?.length ?? 0}`)
  return html.replace(pattern, replacement)
}

const attribute = value => value.replace(/&/g, "&amp;").replace(/"/g, "&quot;")

for (const page of pages) {
  let html = replaceOnce(template, /<div id="root"><\/div>/, `<div id="root">${render(page.route, page.roadmapPage)}</div>`, "#root mount")
  html = replaceOnce(html, /<html lang="en">/, `<html lang="en" data-prerendered-view="${page.view}">`, "<html> tag")
  // The prerendered page is the no-JavaScript fallback, so the short <noscript>
  // summary in index.html would only repeat it.
  html = replaceOnce(html, /\s*<noscript>[\s\S]*?<\/noscript>/, "", "<noscript> summary")
  const { title, description, url, socialTitle, socialDescription } = page.head
  if (title) html = replaceOnce(html, /<title>[^<]*<\/title>/, `<title>${title}</title>`, "<title>")
  if (description) html = replaceOnce(html, /<meta name="description" content="[^"]*" \/>/, `<meta name="description" content="${attribute(description)}" />`, "meta description")
  if (url) {
    html = replaceOnce(html, /<link rel="canonical" href="[^"]*" \/>/, `<link rel="canonical" href="${url}" />`, "canonical link")
    html = replaceOnce(html, /<meta property="og:url" content="[^"]*" \/>/, `<meta property="og:url" content="${url}" />`, "og:url")
  }
  if (socialTitle) {
    html = replaceOnce(html, /<meta property="og:title" content="[^"]*" \/>/, `<meta property="og:title" content="${attribute(socialTitle)}" />`, "og:title")
    html = replaceOnce(html, /<meta name="twitter:title" content="[^"]*" \/>/, `<meta name="twitter:title" content="${attribute(socialTitle)}" />`, "twitter:title")
  }
  if (socialDescription) {
    html = replaceOnce(html, /<meta property="og:description" content="[^"]*" \/>/, `<meta property="og:description" content="${attribute(socialDescription)}" />`, "og:description")
    html = replaceOnce(html, /<meta name="twitter:description" content="[^"]*" \/>/, `<meta name="twitter:description" content="${attribute(socialDescription)}" />`, "twitter:description")
  }
  fs.mkdirSync(page.file.replace(/\/[^/]+$/, ""), { recursive: true })
  fs.writeFileSync(page.file, html)
  console.log(`prerendered ${page.view} into ${page.file} (${Math.round(html.length / 1024)} KiB)`)
}
fs.rmSync("dist-ssr", { recursive: true, force: true })
