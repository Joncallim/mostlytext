// Inserts the server-rendered home page into dist/index.html after `vite build`
// and `vite build --ssr`. The deployable output is still the static dist/ folder.
import fs from "node:fs"
import { pathToFileURL } from "node:url"

const indexPath = "dist/index.html"
const { render } = await import(pathToFileURL("dist-ssr/entry-server.js").href)
const appHtml = render()
let html = fs.readFileSync(indexPath, "utf8")

const mount = '<div id="root"></div>'
if (html.split(mount).length !== 2) throw new Error(`Expected exactly one ${mount} in ${indexPath}`)
html = html.replace(mount, `<div id="root">${appHtml}</div>`)

// The prerendered page is the no-JavaScript fallback, so the short <noscript>
// summary in index.html would only repeat it.
const noscript = /\s*<noscript>[\s\S]*?<\/noscript>/
if (!noscript.test(html)) throw new Error("Expected the <noscript> summary in index.html")
html = html.replace(noscript, "")

fs.writeFileSync(indexPath, html)
fs.rmSync("dist-ssr", { recursive: true, force: true })
console.log(`prerendered home page into ${indexPath} (${Math.round(appHtml.length / 1024)} KiB of markup)`)
