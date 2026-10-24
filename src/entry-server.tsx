import { StrictMode } from "react"
import { renderToString } from "react-dom/server"
import App from "./App"
export { details } from "./roadmapParts"

// Build-time only: renders a page for the given route to static HTML (see scripts/prerender.mjs).
export function render(route: string, roadmapPage: boolean) {
  return renderToString(<StrictMode><App initialRoute={route} roadmapPage={roadmapPage} /></StrictMode>)
}
