import { useEffect, useState } from "react"
import data from "./roadmap-data.json"

type Item = (typeof data.upToOne)[number]
const labels: Record<string, string> = { implemented: "Implemented · prerelease", development: "In development", remaining: "Still required", deferred: "Deferred", undecided: "Undecided", planned: "Later · planned direction", provisional: "Exploring · provisional", horizon: "Exploring · longer term", "demand-gated": "Demand-led" }
const groups = [
  { title: "Write, find, and organise", description: "The everyday editor: files, native windows, precise edits, navigation, and settings.", ids: ["E01", "E02", "E03", "E04", "E05", "E08", "E09", "E10", "E11", "E13", "E18", "E22"] },
  { title: "Explain the technical work", description: "Markdown preview, diagrams, equations, and export, with the remaining correctness and safety work alongside them.", ids: ["E06", "E07", "E12", "E14", "E19", "E20", "E21", "anchors", "resource-security"] },
  { title: "Make it feel at home on Mac", description: "Themes, Finder and Quick Look, accessibility, language quality, and reliable document handling.", ids: ["E15", "E23", "safety", "E16"] },
  { title: "MacDown 2 becomes MostlyText", description: "A visible product crossover: app name and icon, retained settings and document state, the CLI, and the distribution and repository transition. This migration is still ahead.", ids: ["identity", "E17-software", "cutover", "launch-surface", "commercial-direction"] },
  { title: "Get a verified release into your hands", description: "Build foundations, migration, updates, signed candidates, final evidence, and the public release.", ids: ["E00", "S", "V1", "sources", "RC2", "gate115", "release"] },
]
const laterGroups = [
  { title: "Make the everyday work better", description: "1.0.x–1.4: reliability, linked source and preview, tables, importing, and careful rendered editing. Planned directions; detailed scope is still provisional.", ids: ["1.0.x", "1.1", "1.2", "1.3", "1.4"] },
  { title: "Explore richer ways to work", description: "1.5–1.10: broader editing, table views, history, workspaces, links, and publication. Each chapter depends on earlier work proving itself; none has a delivery date.", ids: ["1.5", "1.6", "1.7", "1.8", "1.9", "1.10"] },
  { title: "Let real workflows lead", description: "Longer-term themes, representations, and demand-led possibilities without assigned versions.", ids: ["theme-refresh", "later-adapters", "ipad", "demand-watchlist"] },
  { title: "Deferred or still undecided", description: "Same-document split editing is deferred. Extension approaches need evaluation before any commitment.", ids: ["split", "jsc", "extensionkit"] },
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

function RoadmapItem({ item, expanded }: { item: Item; expanded: boolean }) {
  return <details className="roadmap-work" open={expanded}>
    <summary><span className="work-title">{item.version && <span className="work-version">{item.version}</span>}{item.title}</span><span className={`work-status status-${item.status}`}>{labels[item.status]}</span><span className="disclosure-plus" aria-hidden="true" /></summary>
    <div className="work-detail">
      {item.promise && <p className="work-promise">{item.promise}</p>}
      <ul>{item.features.map(feature => <li key={feature}>{feature}</li>)}</ul>
      {item.notes.length > 0 && <div className="work-notes">{item.notes.map(note => <p key={note}>{note}</p>)}</div>}
      {item.dependsOn.length > 0 && <p className="work-dependencies"><strong>Depends on:</strong> {item.dependsOn.map(id => names[id] || (id === "E16-interim" ? "Interim localisation baseline" : id)).join("; ")}</p>}
      <div className="work-evidence"><span>{item.id}</span>{item.issues.length ? item.issues.map(issue => <a key={issue.url} href={issue.url}>Issue #{issue.number} ↗</a>) : item.planningDirection ? <span>Product direction · October 2026</span> : <a href={item.id === "jsc" || item.id === "extensionkit" ? extensionUrl : planUrl}>Source plan ↗</a>}</div>
    </div>
  </details>
}

export default function Roadmap({ route }: { route: string }) {
  const after = route.includes("after-1")
  const [query, setQuery] = useState("")
  const [status, setStatus] = useState("all")
  const [expanded, setExpanded] = useState(false)
  useEffect(() => { setQuery(""); setStatus("all"); setExpanded(false) }, [after])
  const items = after ? data.postOne : data.upToOne
  const sections = after ? laterGroups : groups
  const matches = (item: Item) => (status === "all" || item.status === status) && `${item.title} ${item.features.join(" ")} ${item.notes.join(" ")} ${item.id}`.toLowerCase().includes(query.toLowerCase().trim())
  const count = items.filter(matches).length

  return <main className="roadmap-document section-frame" id="main-content" tabIndex={-1}>
    <a className="roadmap-back text-link" href="#roadmap">← Back to MostlyText</a>
    <header className="roadmap-document-heading">
      <div><p className="section-number">The full roadmap</p><h1>One Mac release.<br /><em>Then what comes after.</em></h1></div>
      <div className="roadmap-introduction"><p>A clear view of the work toward macOS 1.0, and the product chapters planned beyond it.</p><p>Evidence checked 15 October 2026. A <a href="https://github.com/Joncallim/macdown_2/releases/tag/v0.1.0-alpha.1">source-only testing alpha</a> is available to build yourself. No signed app download or stable 1.0 is available. “Implemented” means development code, not verified 1.0 functionality. No delivery dates are promised.</p></div>
    </header>
    <nav className="roadmap-stage-nav" aria-label="Roadmap stages">
      <a href="#/roadmap" aria-current={!after ? "page" : undefined}>To 1.0 <span>{data.upToOne.length} work areas</span></a>
      <a href="#/roadmap/after-1" aria-current={after ? "page" : undefined}>After 1.0 <span>1.0.x–1.10 &amp; later ideas</span></a>
    </nav>
    {after && <p className="roadmap-stage-note">Version numbers mark the intended chapter sequence, not dates or paid-upgrade promises. Scope is provisional; 1.5 onward is exploratory and may change with evidence and demand.</p>}
    <div className="roadmap-toolbar">
      <label className="roadmap-search">Find a feature<input type="search" value={query} onChange={event => setQuery(event.target.value)} placeholder="Try themes, PDF, iPad…" /></label>
      <label className="roadmap-filter">Status<select value={status} onChange={event => setStatus(event.target.value)}><option value="all">All statuses</option>{Array.from(new Set(items.map(item => item.status))).map(value => <option key={value} value={value}>{labels[value]}</option>)}</select></label>
      <button type="button" className="roadmap-expand" onClick={() => setExpanded(!expanded)}>{expanded ? "Collapse work" : "Expand all work"}</button>
    </div>
    <p className="roadmap-result-count" aria-live="polite">{count} of {items.length} work areas{query && ` matching “${query}”`}</p>
    <div className="roadmap-groups">
      {sections.map((group, index) => {
        const visible = group.ids.map(id => items.find(item => item.id === id)).filter((item): item is Item => Boolean(item)).filter(matches)
        if (!visible.length) return null
        return <section className="roadmap-group" key={`${group.title}:${expanded}:${query}:${status}:${after}`}>
          <header><span className="entry-number">0{index + 1}</span><div><h2>{group.title}</h2><p>{group.description}</p></div></header>
          <details className="roadmap-group-work" open={after || expanded || Boolean(query) || status !== "all"}>
            <summary>Explore {visible.length} work {visible.length === 1 ? "area" : "areas"}<span aria-hidden="true">＋</span></summary>
            <div>{visible.map(item => <RoadmapItem key={item.id} item={item} expanded={expanded || Boolean(query)} />)}</div>
          </details>
        </section>
      })}
      {!count && <div className="roadmap-empty"><p>No matching work areas in this stage.</p><button type="button" onClick={() => { setQuery(""); setStatus("all") }}>Clear filters</button></div>}
    </div>
    {!after && <aside className="release-path"><p className="section-number">The path to release</p><h2>Features are only part of “ready.”</h2><ol><li>Finish features and stabilise the app</li><li>Verify a private signed candidate on Mac</li><li>Finish localisation and freeze the UI</li><li>Build the final candidate with source and licence evidence</li><li>Repeat checks on those exact release files</li><li>Close release requirements and move the repository</li><li>Publish the approved, verified release</li></ol><a className="text-link" href={releaseSequenceUrl}>Read the release sequence ↗</a></aside>}
    {after && <details className="roadmap-extra"><summary>Outside 1.0, with no commitment for later<span aria-hidden="true">＋</span></summary><p>These are explicitly excluded from 1.0. Listing them here does not turn them into a future promise.</p><ul>{data.notCommitted.map(item => <li key={item}>{item}</li>)}</ul></details>}
    <details className="roadmap-extra"><summary>What the status labels mean<span aria-hidden="true">＋</span></summary><dl className="status-legend">{Object.entries(data.statusDefinitions).map(([key, definition]) => <div key={key}><dt>{labels[key]}</dt><dd>{definition}</dd></div>)}</dl></details>
    <details className="roadmap-extra"><summary>Development evidence &amp; source links<span aria-hidden="true">＋</span></summary>
      <p>This is a dated snapshot. The product direction is reconciled with development evidence. Open pull requests and issue acceptance are not release proof. Newer release-sequence and closure records take precedence where older summaries disagree.</p>
      <p className="evidence-commit">Source baseline: <a href={`${data.implementationRepository}/commit/${data.sourceHead}`}>{data.sourceHead.slice(0, 12)}</a> · {data.asOf}</p>
      <h3>Source documents</h3><ul>{data.sources.map(source => <li key={source.url}><a href={source.url}>{sourceNames[source.title] || source.title} ↗</a></li>)}</ul>
      <h3>Open development changes at the snapshot</h3><ul>{data.openPullRequests.map(pr => <li key={pr.number}><a href={pr.url}>#{pr.number}: {pr.title}</a> <span className="evidence-state">Open, not merged</span></li>)}</ul>
      <details className="roadmap-issue-index"><summary>Full open-work issue index ({data.openIssueInventory.length})</summary><ul>{data.openIssueInventory.map(issue => <li key={issue.number}><a href={issue.url}>#{issue.number}: {issue.title}</a></li>)}</ul></details>
    </details>
    <p className="roadmap-bottom"><a href="#/roadmap">To 1.0</a><a href="#/roadmap/after-1">After 1.0</a><a href="#home">Back to home ↑</a></p>
  </main>
}
