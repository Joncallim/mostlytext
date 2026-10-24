// Routes: the home page at "/", the roadmap page at "/roadmap/" (prerendered;
// stages as "?stage=after-1", the form production uses), a detail page for each
// roadmap chapter or version at "/roadmap/<name>/" (prerendered), and the older
// hash view at "/#/roadmap" and "/#/roadmap/after-1". A route is a hash-style
// string; its view is what the page shows, which prerendered HTML must match to
// hydrate.

// Roadmap stages that URLs can name. Anything else shows "To 1.0", as in production.
export const ROADMAP_STAGES = ["after-1"] as const
export type RoadmapStage = "" | (typeof ROADMAP_STAGES)[number]

function knownStage(value: string | null | undefined): RoadmapStage {
  return (ROADMAP_STAGES as readonly string[]).includes(value ?? "") ? value as RoadmapStage : ""
}

// A detail page's name: lower-case letters, digits and hyphens ("write-find-and-organise",
// "1-1", "later"). Paths with a dot, such as /roadmap/index.html, are the roadmap itself.
const DETAIL_PATH = /^\/roadmap\/([a-z0-9-]+)\/?$/

export function detailOf(route: string) {
  const match = /^#\/roadmap\/detail\/([a-z0-9-]+)$/.exec(route)
  return match ? match[1] : ""
}

export function detailRoute(name: string) {
  return `#/roadmap/detail/${name}`
}

export function detailHref(name: string) {
  return `/roadmap/${name}/`
}

export function isRoadmapRoute(route: string) {
  return route.startsWith("#/roadmap")
}

export function stageOf(route: string): RoadmapStage {
  const match = /^#\/roadmap\/([^/]+)\/?$/.exec(route)
  return match ? knownStage(match[1]) : ""
}

export function roadmapRoute(stage: RoadmapStage) {
  return stage ? `#/roadmap/${stage}` : "#/roadmap"
}

export function isRoadmapPage() {
  return typeof window !== "undefined" && window.location.pathname.startsWith("/roadmap")
}

export function routeFromLocation() {
  if (typeof window === "undefined") return ""
  const { pathname, search, hash } = window.location
  if (detailOf(hash)) return hash
  if (isRoadmapRoute(hash)) return roadmapRoute(stageOf(hash))
  const detail = DETAIL_PATH.exec(pathname)
  if (detail) return detailRoute(detail[1])
  if (pathname.startsWith("/roadmap")) return roadmapRoute(knownStage(new URLSearchParams(search).get("stage")))
  return hash
}

export function viewOf(route: string) {
  if (detailOf(route)) return route
  return isRoadmapRoute(route) ? roadmapRoute(stageOf(route)) : "home"
}

// Stage links keep each page's own URL form: the roadmap page uses real URLs,
// the legacy hash view stays on the home page.
export function stageHref(stage: RoadmapStage, roadmapPage: boolean) {
  if (roadmapPage) return stage ? `/roadmap/?stage=${stage}` : "/roadmap/"
  return roadmapRoute(stage)
}
