import { useEffect, useState, type CSSProperties } from "react"
import data from "./roadmap-data.json"
import { ALPHA_URL } from "./links"
import { asOf, ChapterPicture, details, groups, labels, laterGroups, pictures, releaseSequenceUrl, releaseSteps, RoadmapItem, slug, sourceNames, type Detail, type Item } from "./roadmapParts"
import { detailHref, stageHref, type RoadmapStage } from "./route"

// The road in one picture: To 1.0 as chapters sized by their work areas and filled by
// their state, then the 1.0 release, then After 1.0 as one stop per planned version.
// A short card for one chapter or version, shown while the pointer or focus is on it;
// Escape hides it. The link itself opens the detail page.
function MapTip({ detail, id, up }: { detail: Detail; id: string; up: boolean }) {
  // A teaser: what it is and where it stands. The page behind it carries the rest.
  const more = detail.kind === "chapter" ? `Open for why it matters, how it will be checked and its ${detail.items.length} work areas`
    : detail.kind === "later" ? `Open for the ${detail.items.length} ideas, why they’re hard and what isn’t on the roadmap`
    : "Open for an example, why it isn’t simple and where it fits"
  return <span className={`rm-tip${up ? " is-up" : " is-down"}`} id={id} role="tooltip">
    <strong>{detail.title}</strong>
    <span className="rm-tip-state">{detail.state}</span>
    <span className="rm-tip-text">{detail.summary}</span>
    <span className="rm-tip-more">{more}</span>
  </span>
}

function RoadmapMap() {
  // The open card, and whether it opens upwards: below when there is room, above otherwise.
  const [tip, setTip] = useState({ name: "", up: false })
  // Escape closes an open card wherever focus is, including a card opened by the pointer.
  useEffect(() => {
    if (!tip.name) return
    const escape = (event: KeyboardEvent) => { if (event.key === "Escape") setTip({ name: "", up: false }) }
    window.addEventListener("keydown", escape)
    return () => window.removeEventListener("keydown", escape)
  }, [tip.name])
  const chapters = details.filter(detail => detail.kind === "chapter")
  const stops = details.filter(detail => detail.kind !== "chapter")
  const count = (status: string) => data.upToOne.filter(item => item.status === status).length
  const total = data.upToOne.length, merged = count("implemented"), building = count("development")
  const versions = stops.filter(detail => detail.kind === "version"), later = stops.find(detail => detail.kind === "later")!
  // Hover, focus and Escape, shared by every chapter and stop.
  const open = (name: string) => (event: { currentTarget: Element }) => {
    const box = event.currentTarget.getBoundingClientRect()
    // A sticky header covers the top of the window on wide screens; a card above must clear it.
    const header = document.querySelector(".site-header")?.getBoundingClientRect().bottom ?? 0
    setTip({ name, up: box.bottom + 240 > window.innerHeight && box.top - Math.max(0, header) > 240 })
  }
  const close = (name: string) => () => setTip(current => current.name === name ? { name: "", up: false } : current)
  const hover = (name: string) => ({ onPointerEnter: open(name), onPointerLeave: close(name), onFocus: open(name), onBlur: close(name) })
  const tipFor = (detail: Detail) => tip.name === detail.name ? <MapTip detail={detail} id={`tip-${detail.name}`} up={tip.up} /> : null
  const describedBy = (detail: Detail) => tip.name === detail.name ? `tip-${detail.name}` : undefined
  return <figure className="rm-map" aria-labelledby="rm-map-title">
    <h2 id="rm-map-title" className="rm-map-title">Where it stands</h2>
    <p className="rm-map-summary">To 1.0: {merged} of {total} work areas are merged, {building} are being built and {total - merged - building} are still required. After 1.0: {versions.length} planned chapters, from {versions[0].items[0].version} to {versions[versions.length - 1].items[0].version}, then {later.items.length} ideas with no version yet. Point at any part for a summary; select it for the full detail.</p>
    <div className="rm-lane rm-lane-to1">
      <p className="rm-lane-start"><strong>Now</strong><span>Source alpha</span></p>
      <ol className="rm-lane-chapters" style={{ "--cols": chapters.map(c => `${c.items.length}fr`).join(" ") } as CSSProperties}>
        {chapters.map((c, index) => {
          const done = c.items.filter(item => item.status === "implemented").length, built = c.items.filter(item => item.status === "development").length
          return <li key={c.name} className={index >= chapters.length - 2 ? "tip-end" : undefined} {...hover(c.name)}>
            <a href={detailHref(c.name)} aria-label={`${c.title}: ${c.state}`} aria-describedby={describedBy(c)}>
              <span className="rm-seg-name">{c.title}</span>
              <span className="rm-seg-bar" aria-hidden="true"><i className="is-merged" style={{ width: `${(done / c.items.length) * 100}%` }} /><i className="is-building" style={{ width: `${(built / c.items.length) * 100}%` }} /></span>
              <span className="rm-seg-count" aria-hidden="true">{done} of {c.items.length}</span>
            </a>
            {tipFor(c)}
          </li>
        })}
      </ol>
      <p className="rm-lane-end"><strong>1.0</strong><span>Verified Mac release</span></p>
    </div>
    <div className="rm-lane rm-lane-after">
      <p className="rm-lane-start"><strong>Then</strong><span>after 1.0</span></p>
      <ol className="rm-lane-stops">
        {stops.map((d, index) => {
          const isLater = d.kind === "later"
          return <li key={d.name} className={`is-${isLater ? "later" : d.status}${index >= stops.length - 4 ? " tip-end" : ""}`} {...hover(d.name)}>
            <a href={detailHref(d.name)} aria-label={isLater ? `Later: ${d.state} with no version yet` : `${d.title}: ${d.state}`} aria-describedby={describedBy(d)}>
              <span className="rm-stop" aria-hidden="true" />
              <span className="rm-stop-version" aria-hidden="true">{isLater ? "Later" : d.items[0].version}</span>
              <span className="rm-stop-title" aria-hidden="true">{isLater ? d.state : d.items[0].title}</span>
            </a>
            {tipFor(d)}
          </li>
        })}
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
            {!after && <a className="text-link rm-chapter-link" href={detailHref(slug(chapter.title).slice(3))}>The full chapter</a>}
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

    <RoadmapMap />

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
