// Routes: the home page at "/", the roadmap at "/roadmap/" (prerendered) and
// the older "#/roadmap" hash links. A route is a hash-style string; its view
// is what the page shows, which is what prerendered HTML must match to hydrate.
export function routeFromLocation() {
  if (typeof window === "undefined") return ""
  const { pathname, hash } = window.location
  if (hash.startsWith("#/roadmap")) return hash
  return pathname.startsWith("/roadmap") ? "#/roadmap" : hash
}

export function viewOf(route: string) {
  return route.startsWith("#/roadmap") ? route.replace(/\/$/, "") : "home"
}
