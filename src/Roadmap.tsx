import { useEffect, useState, type CSSProperties } from "react"
import data from "./roadmap-data.json"
import { ALPHA_URL } from "./links"
import { stageHref, type RoadmapStage } from "./route"

type Item = (typeof data.upToOne)[number]
const labels: Record<string, string> = { implemented: "Merged", development: "Being built", remaining: "Still required", deferred: "Deferred", undecided: "Undecided", planned: "Planned", provisional: "Exploring", horizon: "Longer term", "demand-gated": "If there’s demand" }
type Picture = { src: string; width: number; height: number; alt: string; caption: string; original: string; small?: boolean }
const capture = "/images/mostlytext-development-workspace.png"
const pictures: Record<string, Picture> = {
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
const slug = (title: string) => "ch-" + title.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")
const groups = [
  { title: "Write, find and organise", description: "The everyday editor: files, native windows, precise edits, navigation and settings.", ids: ["E01", "E02", "E03", "E04", "E05", "E08", "E09", "E10", "E11", "E13", "E18", "E22"] },
  { title: "Explain the technical work", description: "Markdown preview, diagrams, equations and export, with the correctness and safety work they still need.", ids: ["E06", "E07", "E12", "E14", "E19", "E20", "E21", "anchors", "resource-security"] },
  { title: "Feel at home on a Mac", description: "Themes, Finder and Quick Look, accessibility, language quality and reliable document handling.", ids: ["E15", "E23", "safety", "E16"] },
  { title: "The move to MostlyText", description: "MacDown 2 becomes MostlyText. The visible crossover: the app's name and icon, kept settings and documents, the CLI, distribution and the repository move. Still ahead.", ids: ["identity", "E17-software", "cutover", "launch-surface", "commercial-direction"] },
  { title: "A verified release", description: "Build foundations, migration, updates, signed candidates, final evidence and the public release.", ids: ["E00", "S", "V1", "sources", "RC2", "gate115", "release"] },
]
const laterGroups = [
  { title: "Make everyday work better", description: "Reliability, linked source and preview, tables, importing and careful rendered editing. Planned directions; the detail is still provisional.", ids: ["1.0.x", "1.1", "1.2", "1.3", "1.4"] },
  { title: "Richer ways to work", description: "Broader editing, table views, history, workspaces, links and publishing. Each chapter depends on the earlier ones proving themselves.", ids: ["1.5", "1.6", "1.7", "1.8", "1.9", "1.10"] },
  { title: "Let real workflows lead", description: "Longer-term themes, other representations and possibilities that wait for demand. No versions assigned.", ids: ["theme-refresh", "later-adapters", "ipad", "demand-watchlist"] },
  { title: "Deferred or undecided", description: "Same-document split editing is deferred. Extension approaches need evaluating before any commitment.", ids: ["split", "jsc", "extensionkit"] },
]
const allItems = [...data.upToOne, ...data.postOne]
const names = Object.fromEntries(allItems.map(item => [item.id, item.title]))
const sourceNames: Record<string, string> = {
  "planning/epics/README.md": "Epic index", "planning/MIGRATION_PLAN.md": "Overall development plan",
  "planning/RELEASE_EVIDENCE.md": "Release evidence", "planning/CLOSURE_REGISTER.md": "Current closure register",
  "planning/RELEASE_SEQUENCE.md": "Release sequence", "planning/downstream/readiness.json": "Readiness dependencies",
  "planning/RELEASE_PATH.md": "Release path", "planning/extension-api-design.md": "Extension design exploration",
  "MacDown2/project.yml": "Current build configuration",
}
const planUrl = "https://github.com/Joncallim/macdown_2/blob/master/planning/MIGRATION_PLAN.md"
const extensionUrl = "https://github.com/Joncallim/macdown_2/blob/master/planning/extension-api-design.md"
const releaseSequenceUrl = "https://github.com/Joncallim/macdown_2/blob/master/planning/RELEASE_SEQUENCE.md"
const releaseSteps = ["Finish features and stabilise the app", "Verify a private signed candidate on a Mac", "Finish localisation and freeze the interface", "Build the final candidate with source and licence evidence", "Repeat the checks on those exact release files", "Close the release requirements and move the repository", "Publish the approved, verified release"]
const asOf = new Date(`${data.asOf}T12:00:00Z`).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" })

function RoadmapItem({ item, expanded }: { item: Item; expanded: boolean }) {
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
      <p className="work-evidence">{item.issues.length ? item.issues.map(issue => <a key={issue.url} href={issue.url}>Issue {issue.number}</a>) : item.planningDirection ? <span>Product direction, October 2026</span> : <a href={item.id === "jsc" || item.id === "extensionkit" ? extensionUrl : planUrl}>Source plan</a>}<span className="work-ref">Plan reference {item.id}</span></p>
    </div>
  </details>
}

function ChapterPicture({ picture }: { picture: Picture }) {
  return <figure className={`rm-picture${picture.small ? " is-small" : ""}`} data-reveal>
    <a href={picture.original} target="_blank" rel="noopener noreferrer" aria-label="Open the full-size image (opens in a new tab)">
      <img src={picture.src} width={picture.width} height={picture.height} loading="lazy" decoding="async" alt={picture.alt} />
    </a>
    <figcaption>{picture.caption}</figcaption>
  </figure>
}

// The road in one picture: To 1.0 as chapters sized by their work areas and filled by
// their state, then the 1.0 release, then After 1.0 as one stop per planned version.
const laterStatus = (status: string) => status === "planned" ? "planned" : "exploring"
function RoadmapMap({ roadmapPage }: { roadmapPage: boolean }) {
  const to1 = groups.map(group => {
    const items = group.ids.map(id => data.upToOne.find(item => item.id === id)).filter((item): item is Item => Boolean(item))
    const count = (status: string) => items.filter(item => item.status === status).length
    return { title: group.title, total: items.length, merged: count("implemented"), building: count("development") }
  })
  const total = to1.reduce((sum, g) => sum + g.total, 0), merged = to1.reduce((sum, g) => sum + g.merged, 0), building = to1.reduce((sum, g) => sum + g.building, 0)
  const versions = data.postOne.filter(item => item.version)
  const later = data.postOne.filter(item => !item.version)
  const toLink = (title: string) => roadmapPage ? `/roadmap/#${slug(title)}` : stageHref("", false)
  const afterLink = (id: string) => {
    const group = laterGroups.find(g => g.ids.includes(id))
    return roadmapPage ? `/roadmap/?stage=after-1#${slug(group ? group.title : "")}` : stageHref("after-1", false)
  }
  return <figure className="rm-map" aria-labelledby="rm-map-title">
    <h2 id="rm-map-title" className="rm-map-title">Where it stands</h2>
    <p className="rm-map-summary">To 1.0: {merged} of {total} work areas are merged, {building} are being built and {total - merged - building} are still required. After 1.0: {versions.length} planned chapters, from {versions[0].version} to {versions[versions.length - 1].version}, then {later.length} ideas with no version yet.</p>
    <div className="rm-lane rm-lane-to1">
      <p className="rm-lane-start"><strong>Now</strong><span>Source alpha</span></p>
      <ol className="rm-lane-chapters" style={{ "--cols": to1.map(g => `${g.total}fr`).join(" ") } as CSSProperties}>
        {to1.map(g => <li key={g.title}>
          <a href={toLink(g.title)} aria-label={`${g.title}: ${g.merged} of ${g.total} merged${g.building ? `, ${g.building} being built` : ""}`}>
            <span className="rm-seg-name">{g.title}</span>
            <span className="rm-seg-bar" aria-hidden="true"><i className="is-merged" style={{ width: `${(g.merged / g.total) * 100}%` }} /><i className="is-building" style={{ width: `${(g.building / g.total) * 100}%` }} /></span>
            <span className="rm-seg-count" aria-hidden="true">{g.merged} of {g.total}</span>
          </a>
        </li>)}
      </ol>
      <p className="rm-lane-end"><strong>1.0</strong><span>Verified Mac release</span></p>
    </div>
    <div className="rm-lane rm-lane-after">
      <p className="rm-lane-start"><strong>Then</strong><span>after 1.0</span></p>
      <ol className="rm-lane-stops">
        {versions.map(item => <li key={item.id} className={`is-${laterStatus(item.status)}`}>
          <a href={afterLink(item.id)} aria-label={`${item.version}, ${item.title}: ${laterStatus(item.status) === "planned" ? "planned" : "exploring"}`}>
            <span className="rm-stop" aria-hidden="true" />
            <span className="rm-stop-version" aria-hidden="true">{item.version}</span>
            <span className="rm-stop-title" aria-hidden="true">{item.title}</span>
          </a>
        </li>)}
        <li className="is-later"><a href={afterLink(later[0].id)} aria-label={`Later: ${later.length} ideas with no version yet`}><span className="rm-stop" aria-hidden="true" /><span className="rm-stop-version" aria-hidden="true">Later</span><span className="rm-stop-title" aria-hidden="true">{later.length} ideas</span></a></li>
      </ol>
    </div>
    <ul className="rm-legend" aria-label="Key">
      <li><i className="is-merged" />Merged</li><li><i className="is-building" />Being built</li><li><i className="is-required" />Still required</li><li><i className="is-planned" />Planned</li><li><i className="is-exploring" />Exploring</li>
    </ul>
  </figure>
}

type Filters = { query: string; status: string; expanded: boolean }
const noFilters: Filters = { query: "", status: "all", expanded: false }
const stages = [
  { key: "to-1", after: false, title: "To 1.0", summary: `${data.upToOne.length} work areas` },
  { key: "after-1", after: true, title: "After 1.0", summary: "1.0.x to 1.10, and later ideas" },
] as const
const matcher = ({ query, status }: Filters) => (item: Item) => (status === "all" || item.status === status) && `${item.title} ${item.features.join(" ")} ${item.notes.join(" ")} ${item.promise} ${item.id}`.toLowerCase().includes(query.toLowerCase().trim())

// One stage, as chapters: each chapter's name and progress hold on the left while its
// work areas pass on the right. The active stage gets the visitor's filters; the other
// is rendered unfiltered so the static page carries both stages.
function StageWork({ after, filters, onClear }: { after: boolean; filters: Filters; onClear?: () => void }) {
  const items = after ? data.postOne : data.upToOne
  const chapters = after ? laterGroups : groups
  const matches = matcher(filters)
  const filtering = Boolean(filters.query.trim()) || filters.status !== "all"
  const count = items.filter(matches).length
  return <>
    <div className="rm-chapters">
      {chapters.map(chapter => {
        const all = chapter.ids.map(id => items.find(item => item.id === id)).filter((item): item is Item => Boolean(item))
        const visible = all.filter(matches)
        if (!visible.length) return null
        const done = all.filter(item => item.status === "implemented").length
        const state = after ? (all[0].version ? `${all[0].version}${all.length > 1 && all[all.length - 1].version ? ` to ${all[all.length - 1].version}` : ""}` : "No version yet") : `${done} of ${all.length} merged`
        return <section className="rm-chapter" id={slug(chapter.title)} key={chapter.title} aria-label={chapter.title}>
          <div className="rm-chapter-head" data-reveal>
            <h3>{chapter.title}</h3>
            <p className="rm-chapter-state">{state}</p>
            <p className="rm-chapter-text">{chapter.description}</p>
            {!after && <p className="rm-meter" aria-hidden="true">{all.map(item => <span key={item.id} className={`is-${item.status}`} />)}</p>}
            {pictures[chapter.title] && <ChapterPicture picture={pictures[chapter.title]} />}
          </div>
          <div className="rm-items">
            {filtering && <p className="rm-shown">{visible.length} of {all.length} shown</p>}
            {visible.map(item => <RoadmapItem key={item.id} item={item} expanded={filters.expanded || Boolean(filters.query.trim())} />)}
          </div>
        </section>
      })}
      {!count && onClear && <div className="roadmap-empty"><p>Nothing in this stage matches.</p><button type="button" className="text-button" onClick={onClear}>Clear the search</button></div>}
    </div>
    {!after && <section className="release-path" aria-labelledby="release-path-title">
      <h3 id="release-path-title">Features are only part of “ready”</h3>
      <p>After the features, a release still has to be proved. These happen in order:</p>
      <ol>{releaseSteps.map(step => <li key={step}>{step}</li>)}</ol>
      <a className="text-link" href={releaseSequenceUrl}>Read the release sequence</a>
    </section>}
    {after && <details className="roadmap-extra"><summary>Outside 1.0, with no commitment for later<i aria-hidden="true" /></summary><div><p>These are explicitly excluded from 1.0. Listing them here does not turn them into a promise.</p><ul>{data.notCommitted.map(item => <li key={item}>{item}</li>)}</ul></div></details>}
  </>
}

// Both stages are in the HTML. With JavaScript, one shows at a time and the stage links
// use the URL (/roadmap/?stage=after-1 or #/roadmap/after-1). Without it, both show
// under their own headings with anchor links between them.
export default function Roadmap({ stage, roadmapPage }: { stage: RoadmapStage; roadmapPage: boolean }) {
  const after = stage === "after-1"
  const stageLink = (isAfter: boolean) => stageHref(isAfter ? "after-1" : "", roadmapPage)
  const [query, setQuery] = useState("")
  const [status, setStatus] = useState("all")
  const [expanded, setExpanded] = useState(false)
  useEffect(() => { setQuery(""); setStatus("all"); setExpanded(false) }, [after])
  const items = after ? data.postOne : data.upToOne
  const filters = { query, status, expanded }
  const count = items.filter(matcher(filters)).length
  const statuses = Array.from(new Set(items.map(item => item.status)))

  return <main className="rm" id="main-content" tabIndex={-1}>
    <header className="rm-head">
      <a className="text-link rm-back" href="/#roadmap">MostlyText home</a>
      <h1>The road to 1.0, and after</h1>
      <p className="rm-lead">Every piece of work between today’s source alpha and a verified Mac release, then the chapters planned beyond it.</p>
      <p className="rm-facts">Checked against the development repository on {asOf}. A <a href={ALPHA_URL}>source-only alpha</a> is available to build yourself; there is no ready-to-install app and no 1.0 yet. “Merged” means the work is in the development code, not that it is verified for 1.0. No dates are promised.</p>
    </header>

    <RoadmapMap roadmapPage={roadmapPage} />

    <nav className="roadmap-stage-nav js-only" aria-label="Roadmap stages">
      {stages.map(s => <a key={s.key} href={stageLink(s.after)} aria-current={s.after === after ? "page" : undefined}><strong>{s.title}</strong><span>{s.summary}</span></a>)}
    </nav>
    <nav className="roadmap-anchor-nav no-js-only" aria-label="Roadmap stages on this page">
      <p>On this page</p>
      {stages.map(s => <a key={s.key} href={`#stage-${s.key}`}><strong>{s.title}</strong><span>{s.summary}</span></a>)}
    </nav>

    <div className="roadmap-toolbar js-only" role="search">
      <label className="rm-find" htmlFor="rm-query">Find a feature</label>
      <input id="rm-query" className="rm-query" type="search" value={query} onChange={event => setQuery(event.target.value)} placeholder="PDF, themes, iPad…" autoComplete="off" />
      <div className="rm-filters">
        <div className="segmented" role="radiogroup" aria-label="Status">
          {["all", ...statuses].map(value => <button key={value} type="button" role="radio" aria-checked={status === value} onClick={() => setStatus(value)}>{value === "all" ? "Everything" : labels[value]}</button>)}
        </div>
        <button type="button" className="text-button roadmap-expand" onClick={() => setExpanded(!expanded)}>{expanded ? "Close every work area" : "Open every work area"}</button>
      </div>
      <p className="roadmap-result-count" aria-live="polite">{count} of {items.length} work areas{query.trim() && ` matching “${query.trim()}”`}</p>
    </div>

    {stages.map(s => <section key={s.key} id={`stage-${s.key}`} className={`roadmap-stage${s.after === after ? "" : " roadmap-stage-inactive"}`} aria-labelledby={`stage-${s.key}-title`}>
      <h2 className="roadmap-stage-title" id={`stage-${s.key}-title`}>{s.title} <span>{s.summary}</span></h2>
      {s.after && <p className="roadmap-stage-note">Version numbers mark the intended order of chapters, not dates or paid upgrades. Scope is provisional, and 1.5 onwards is exploratory and may change with evidence and demand.</p>}
      <StageWork after={s.after} filters={s.after === after ? filters : noFilters} onClear={s.after === after ? () => { setQuery(""); setStatus("all") } : undefined} />
    </section>)}

    <div className="rm-reference">
      <details className="roadmap-extra"><summary>What the status labels mean<i aria-hidden="true" /></summary><dl className="status-legend">{Object.entries(data.statusDefinitions).map(([key, definition]) => <div key={key}><dt>{labels[key]}</dt><dd>{definition}</dd></div>)}</dl></details>
      <details className="roadmap-extra"><summary>Development evidence and sources<i aria-hidden="true" /></summary>
        <div>
          <p>This is a dated snapshot. Open pull requests and accepted issues are not release proof, and newer release-sequence and closure records take precedence where older summaries disagree.</p>
          <p className="evidence-commit">Source baseline <a href={`${data.implementationRepository}/commit/${data.sourceHead}`}><code>{data.sourceHead.slice(0, 12)}</code></a>, {asOf}.</p>
          <h3>Source documents</h3><ul>{data.sources.map(source => <li key={source.url}><a href={source.url}>{sourceNames[source.title] || source.title}</a></li>)}</ul>
          <h3>Open development changes at the snapshot</h3><ul>{data.openPullRequests.map(pr => <li key={pr.number}><a href={pr.url}>Pull request {pr.number}: {pr.title}</a> <span className="evidence-state">open, not merged</span></li>)}</ul>
          <details className="roadmap-issue-index"><summary>Every open issue at the snapshot ({data.openIssueInventory.length})</summary><ul>{data.openIssueInventory.map(issue => <li key={issue.number}><a href={issue.url}>Issue {issue.number}: {issue.title}</a></li>)}</ul></details>
        </div>
      </details>
    </div>
    <p className="roadmap-bottom">
      {stages.map(s => <a key={s.key} className="js-only" href={stageLink(s.after)}>{s.title}</a>)}
      {stages.map(s => <a key={`${s.key}-anchor`} className="no-js-only" href={`#stage-${s.key}`}>{s.title}</a>)}
      <a href="/#home">Back to MostlyText</a>
    </p>
  </main>
}
