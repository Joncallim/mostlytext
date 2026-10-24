import data from "./roadmap-data.json"
import { detailHref } from "./route"

// The roadmap's shared model: labels, chapters, pictures and the detail pages that the
// roadmap page, its diagram, the detail pages and the prerender step all read.
export type Item = (typeof data.upToOne)[number]
export const labels: Record<string, string> = { implemented: "Merged", development: "Being built", remaining: "Still required", deferred: "Deferred", undecided: "Undecided", planned: "Planned", provisional: "Exploring", horizon: "Longer term", "demand-gated": "If there’s demand" }
export type Picture = { src: string; width: number; height: number; alt: string; caption: string; original: string; small?: boolean }
const capture = "/images/mostlytext-development-workspace.png"
export const pictures: Record<string, Picture> = {
  "Write, find and organise": { src: "/images/mostlytext-roadmap-sidebar.webp", width: 866, height: 669, original: capture,
    caption: "Merged: the Folder, Outline and Search sidebar beside the source. Each heading is a place in the outline.",
    alt: "MostlyText development build: the sidebar with Folder, Outline and Search sections beside the Markdown source, whose headings appear in the outline." },
  "Explain the technical work": { src: "/images/mostlytext-roadmap-preview.webp", width: 945, height: 722, original: capture,
    caption: "Merged: the native Markdown preview, with syntax-highlighted code. Diagrams and math also render; their correctness work is still required.",
    alt: "MostlyText development build: the rendered preview with a heading, a bulleted checklist, a syntax-highlighted Swift code block and a quotation." },
  "Feel at home on a Mac": { src: "/images/mostlytext-roadmap-titlebar.webp", width: 1200, height: 400, original: capture,
    caption: "A native window and document: an untitled file offers Save As with the standard shortcut. Finder, Quick Look, themes and localisation are still ahead.",
    alt: "MostlyText development build: the corner of a native macOS window with its controls, a document bar reading “Untitled — Save As… ⌘⇧S to name this document”, the folder panel and the first lines of Markdown." },
  "The move to MostlyText": { src: "/images/mostlytext-development-finder-icon.png", width: 360, height: 322, small: true, original: "/images/mostlytext-development-finder-icon.png",
    caption: "Done in September: the new MostlyText icon on a real build in Finder. The app is still called MacDown2.app; renaming it is this chapter’s work.",
    alt: "A Finder window on a Mac showing the MostlyText icon, a slanted M and T, on an app still named MacDown2.app." },
}
export const slug = (title: string) => "ch-" + title.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")
export const groups = [
  { title: "Write, find and organise", description: "The everyday editor: files, native windows, precise edits, navigation and settings.", ids: ["E01", "E02", "E03", "E04", "E05", "E08", "E09", "E10", "E11", "E13", "E18", "E22"] },
  { title: "Explain the technical work", description: "Markdown preview, diagrams, equations and export, with the correctness and safety work they still need.", ids: ["E06", "E07", "E12", "E14", "E19", "E20", "E21", "anchors", "resource-security"] },
  { title: "Feel at home on a Mac", description: "Themes, Finder and Quick Look, accessibility, language quality and reliable document handling.", ids: ["E15", "E23", "safety", "E16"] },
  { title: "The move to MostlyText", description: "MacDown 2 becomes MostlyText. The visible crossover: the app's name and icon, kept settings and documents, the CLI, distribution and the repository move. Still ahead.", ids: ["identity", "E17-software", "cutover", "launch-surface", "commercial-direction"] },
  { title: "A verified release", description: "Build foundations, migration, updates, signed candidates, final evidence and the public release.", ids: ["E00", "S", "V1", "sources", "RC2", "gate115", "release"] },
]
export const laterGroups = [
  { title: "Make everyday work better", description: "Reliability, linked source and preview, tables, importing and careful rendered editing. Planned directions; the detail is still provisional.", ids: ["1.0.x", "1.1", "1.2", "1.3", "1.4"] },
  { title: "Richer ways to work", description: "Broader editing, table views, history, workspaces, links and publishing. Each chapter depends on the earlier ones proving themselves.", ids: ["1.5", "1.6", "1.7", "1.8", "1.9", "1.10"] },
  { title: "Let real workflows lead", description: "Longer-term themes, other representations and possibilities that wait for demand. No versions assigned.", ids: ["theme-refresh", "later-adapters", "ipad", "demand-watchlist"] },
  { title: "Deferred or undecided", description: "Same-document split editing is deferred. Extension approaches need evaluating before any commitment.", ids: ["split", "jsc", "extensionkit"] },
]
const allItems = [...data.upToOne, ...data.postOne]
export const names = Object.fromEntries(allItems.map(item => [item.id, item.title]))
export const sourceNames: Record<string, string> = {
  "planning/epics/README.md": "Epic index", "planning/MIGRATION_PLAN.md": "Overall development plan",
  "planning/RELEASE_EVIDENCE.md": "Release evidence", "planning/CLOSURE_REGISTER.md": "Current closure register",
  "planning/RELEASE_SEQUENCE.md": "Release sequence", "planning/downstream/readiness.json": "Readiness dependencies",
  "planning/RELEASE_PATH.md": "Release path", "planning/extension-api-design.md": "Extension design exploration",
  "MacDown2/project.yml": "Current build configuration",
}
export const planUrl = "https://github.com/Joncallim/macdown_2/blob/master/planning/MIGRATION_PLAN.md"
export const extensionUrl = "https://github.com/Joncallim/macdown_2/blob/master/planning/extension-api-design.md"
export const releaseSequenceUrl = "https://github.com/Joncallim/macdown_2/blob/master/planning/RELEASE_SEQUENCE.md"
export const releaseSteps = ["Finish features and stabilise the app", "Verify a private signed candidate on a Mac", "Finish localisation and freeze the interface", "Build the final candidate with source and licence evidence", "Repeat the checks on those exact release files", "Close the release requirements and move the repository", "Publish the approved, verified release"]
export const asOf = new Date(`${data.asOf}T12:00:00Z`).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" })

export function RoadmapItem({ item, expanded }: { item: Item; expanded: boolean }) {
  return <details className={`roadmap-work status-${item.status}`} open={expanded} data-reveal>
    <summary>
      {item.version && <span className="work-version">{item.version}</span>}
      <span className="work-title">{item.title}</span>
      <span className="work-status">{labels[item.status]}</span>
      <i aria-hidden="true" />
    </summary>
    <div className="work-detail">
      {item.promise && <p className="work-promise">{item.promise}</p>}
      <ul>{item.features.map(feature => <li key={feature}>{feature}</li>)}</ul>
      {item.notes.length > 0 && <div className="work-notes">{item.notes.map(note => <p key={note}>{note}</p>)}</div>}
      {item.dependsOn.length > 0 && <p className="work-dependencies">Depends on {item.dependsOn.map(id => names[id] || (id === "E16-interim" ? "Interim localisation baseline" : id)).join("; ")}.</p>}
      <p className="work-evidence">{item.issues.length ? item.issues.map(issue => <a key={issue.url} href={issue.url}>Issue {issue.number}</a>) : item.planningDirection ? <span>Product direction, October 2026</span> : <a href={item.id === "jsc" || item.id === "extensionkit" ? extensionUrl : planUrl}>Source plan</a>}<span className="work-ref">Plan reference {item.id}</span>{item.version && <a href={detailHref(item.version.replace(/\./g, "-"))}>More about {item.version}</a>}</p>
    </div>
  </details>
}

export function ChapterPicture({ picture }: { picture: Picture }) {
  return <figure className={`rm-picture${picture.small ? " is-small" : ""}`} data-reveal>
    <a href={picture.original} target="_blank" rel="noopener noreferrer" aria-label="Open the full-size image (opens in a new tab)">
      <img src={picture.src} width={picture.width} height={picture.height} loading="lazy" decoding="async" alt={picture.alt} />
    </a>
    <figcaption>{picture.caption}</figcaption>
  </figure>
}


// One detail page per To 1.0 chapter, per planned version and one for the ideas with no
// version, each at /roadmap/<name>/.
export type Detail = { name: string; kind: "chapter" | "version" | "later"; title: string; summary: string; state: string; status: string; items: Item[]; picture?: Picture }
const itemsOf = (ids: string[], list: Item[]) => ids.map(id => list.find(item => item.id === id)).filter((item): item is Item => Boolean(item))
export const laterStatus = (status: string) => status === "planned" ? "planned" : "exploring"
export const details: Detail[] = [
  ...groups.map(group => {
    const items = itemsOf(group.ids, data.upToOne)
    const merged = items.filter(item => item.status === "implemented").length, building = items.filter(item => item.status === "development").length
    return { name: slug(group.title).slice(3), kind: "chapter" as const, title: group.title, summary: group.description, items, picture: pictures[group.title],
      status: merged === items.length ? "merged" : "mixed",
      state: `${merged} of ${items.length} merged${building ? `, ${building} being built` : ""}` }
  }),
  ...data.postOne.filter(item => item.version).map(item => ({ name: item.version.replace(/\./g, "-"), kind: "version" as const, title: `${item.version} ${item.title}`,
    summary: item.promise || item.features[0], items: [item], status: laterStatus(item.status), state: labels[item.status] })),
  (() => {
    const items = data.postOne.filter(item => !item.version)
    return { name: "later", kind: "later" as const, title: "Later, with no version yet", summary: `${items.length} ideas with no version yet: longer-term themes, an iPhone and iPad exploration, and approaches still to evaluate.`, items, status: "exploring", state: `${items.length} ideas` }
  })(),
]
export const detailNamed = (name: string) => details.find(detail => detail.name === name)

// Which detail page a work area belongs to, so dependencies can link page to page.
const pageOf: Record<string, string> = Object.fromEntries(details.flatMap(detail => detail.items.map(item => [item.id, detail.name])))
const unique = (list: Detail[]) => list.filter((detail, index) => list.indexOf(detail) === index)
export function relations(detail: Detail) {
  const own = new Set(detail.items.map(item => item.id))
  const buildsOn = unique(detail.items.flatMap(item => item.dependsOn).filter(id => !own.has(id) && pageOf[id]).map(id => detailNamed(pageOf[id])!).filter(other => other !== detail))
  const leadsTo = unique(details.filter(other => other !== detail && other.items.some(item => item.dependsOn.some(id => own.has(id)))))
  return { buildsOn, leadsTo }
}
export function openWork(detail: Detail, pullRequests: number[] = []) {
  const numbers = new Set(detail.items.flatMap(item => item.issues.map(issue => issue.number)))
  return {
    issues: data.openIssueInventory.filter(issue => numbers.has(issue.number)),
    pullRequests: pullRequests.map(number => data.openPullRequests.find(pull => pull.number === number)).filter(pull => pull !== undefined),
  }
}
