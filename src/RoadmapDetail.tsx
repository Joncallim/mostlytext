import { detailHref } from "./route"
import { asOf, ChapterPicture, detailNamed, details, extensionUrl, labels, names, planUrl, type Item } from "./roadmapParts"

// One work area written out in full: the detail page is the document, so nothing folds.
function WorkEntry({ item, showPromise }: { item: Item; showPromise: boolean }) {
  return <article className="rm-entry" data-reveal>
    <header className="rm-entry-head">
      <h3>{item.version && <span className="work-version">{item.version}</span>}{item.title}</h3>
      <p className={`rm-entry-status status-${item.status}`}>{labels[item.status]}</p>
    </header>
    {showPromise && item.promise && <p className="work-promise">{item.promise}</p>}
    <ul className="rm-entry-features">{item.features.map(feature => <li key={feature}>{feature}</li>)}</ul>
    {item.notes.length > 0 && <div className="rm-entry-notes">{item.notes.map(note => <p key={note}>{note}</p>)}</div>}
    {item.dependsOn.length > 0 && <p className="work-dependencies">Depends on {item.dependsOn.map(id => names[id] || (id === "E16-interim" ? "Interim localisation baseline" : id)).join("; ")}.</p>}
    <p className="work-evidence">{item.issues.length ? item.issues.map(issue => <a key={issue.url} href={issue.url}>Issue {issue.number}</a>) : item.planningDirection ? <span>Product direction, October 2026</span> : <a href={item.id === "jsc" || item.id === "extensionkit" ? extensionUrl : planUrl}>Source plan</a>}<span className="work-ref">Plan reference {item.id}</span></p>
  </article>
}

export default function RoadmapDetail({ name }: { name: string }) {
  const detail = detailNamed(name)
  if (!detail) return <main className="rm rm-detail" id="main-content" tabIndex={-1}>
    <h1>Not on the roadmap</h1>
    <p className="rm-lead">There is no roadmap page called “{name}”. <a href="/roadmap/">See the whole roadmap</a>.</p>
  </main>
  const index = details.indexOf(detail), previous = details[index - 1], next = details[index + 1]
  const chapter = detail.kind === "chapter"
  const merged = detail.items.filter(item => item.status === "implemented").length
  return <main className="rm rm-detail" id="main-content" tabIndex={-1}>
    <nav className="rm-crumbs" aria-label="Breadcrumb">
      <a href="/roadmap/">The roadmap</a>
      <a href={chapter ? "/roadmap/" : "/roadmap/?stage=after-1"}>{chapter ? "To 1.0" : "After 1.0"}</a>
    </nav>
    <div className="rm-detail-side">
    <header className="rm-detail-head">
      <h1>{detail.title}</h1>
      <p className="rm-detail-state">{detail.state}</p>
      {chapter && <p className="rm-meter" aria-hidden="true">{detail.items.map(item => <span key={item.id} className={`is-${item.status}`} />)}</p>}
      <p className="rm-lead">{detail.summary}</p>
      <p className="rm-facts">{chapter
        ? `One of the five chapters on the way to 1.0: ${merged} of its ${detail.items.length} work areas are merged into the development code, which is not the same as verified for release.`
        : "After 1.0. Version numbers mark the intended order, not dates or paid upgrades; scope is provisional and may change with evidence and demand."} Checked against the development repository on {asOf}.</p>
    </header>
    {detail.picture && <ChapterPicture picture={detail.picture} />}
    </div>
    <section className="rm-detail-work" aria-labelledby="rm-work-title">
      <h2 id="rm-work-title">{chapter ? `The ${detail.items.length} work areas` : detail.kind === "later" ? `The ${detail.items.length} ideas` : "What it covers"}</h2>
      {detail.items.map(item => <WorkEntry key={item.id} item={item} showPromise={detail.kind !== "version"} />)}
    </section>
    <nav className="rm-pager" aria-label="Along the roadmap">
      {previous ? <a href={detailHref(previous.name)} data-reveal><span>Before this</span><strong>{previous.title}</strong></a> : <span />}
      {next ? <a href={detailHref(next.name)} className="rm-pager-next" data-reveal><span>After this</span><strong>{next.title}</strong></a> : <a href="/roadmap/" className="rm-pager-next" data-reveal><span>Back to</span><strong>The whole roadmap</strong></a>}
    </nav>
  </main>
}
