import { StrictMode } from "react"
import { renderToString } from "react-dom/server"
import App from "./App"

// Build-time only: renders the home page to static HTML (see scripts/prerender.mjs).
export function render() {
  return renderToString(<StrictMode><App /></StrictMode>)
}
