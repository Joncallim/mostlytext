import type React from "react"
import { detailHref } from "./route"
import { asOf, ChapterPicture, detailNamed, details, extensionUrl, labels, names, openWork, planUrl, relations, type Detail, type Item } from "./roadmapParts"
import { narratives, statusMeanings } from "./roadmapNarrative"

// One work area written out in full: the detail page is the document, so nothing folds.
function WorkEntry({ item, showPromise }: { item: Item; showPromise: boolean }) {
  return <article className="rm-entry" tabIndex={-1} id={`work-${item.id.toLowerCase().replace(/[^a-z0-9]+/g, "-")}`} data-reveal>
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

const anchorOf = (item: Item) => `#work-${item.id.toLowerCase().replace(/[^a-z0-9]+/g, "-")}`
// Scroll within the page without changing the hash, which also carries the route in the preview.
function jump(event: React.MouseEvent<HTMLAnchorElement>) {
  const target = document.getElementById(event.currentTarget.hash.slice(1))
  if (!target) return
  event.preventDefault()
  target.scrollIntoView({ behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" })
  target.focus({ preventScroll: true })
}

// A chapter's progress, by status, each title linking down to its full entry.
function Standing({ detail }: { detail: Detail }) {
  const order = ["implemented", "development", "remaining"]
  return <div className="rm-standing">
    {order.map(status => {
      const items = detail.items.filter(item => item.status === status)
      return items.length > 0 && <div key={status} className={`rm-standing-group status-${status}`}>
        <h3><span className="rm-standing-count">{items.length}</span> {labels[status].toLowerCase()}</h3>
        <ul>{items.map(item => <li key={item.id}><a href={anchorOf(item)} onClick={jump}>{item.title}</a></li>)}</ul>
      </div>
    })}
  </div>
}

function PageLinks({ title, list }: { title: string; list: Detail[] }) {
  return <div className="rm-links-group">
    <h3>{title}</h3>
    {list.length ? <ul>{list.map(other => <li key={other.name}><a href={detailHref(other.name)}><strong>{other.title}</strong><span>{other.state}</span></a></li>)}</ul> : <p>Nothing else on the roadmap.</p>}
  </div>
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
  const story = narratives[detail.name] ?? { intro: [] }
  const { buildsOn, leadsTo } = relations(detail)
  // "Later" has no single parent, so its builds-on list would only repeat the release.
  const showLinks = detail.kind !== "later"
  const open = openWork(detail, story.pullRequests)
  const statuses = [...new Set(detail.items.map(item => item.status))]
  const workTitle = chapter ? `The ${detail.items.length} work areas` : detail.kind === "later" ? `The ${detail.items.length} ideas` : "What it covers"
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
    <div className="rm-detail-body">
      {story.intro.length > 0 && <section className="rm-story" aria-labelledby="rm-story-title" data-reveal>
        <h2 id="rm-story-title">In short</h2>
        {story.intro.map(paragraph => <p key={paragraph}>{paragraph}</p>)}
      </section>}
      {story.practice && <section className="rm-practice" aria-labelledby="rm-practice-title" data-reveal>
        <h2 id="rm-practice-title">In practice</h2>
        <p>{story.practice}</p>
      </section>}
      {chapter && <section aria-labelledby="rm-standing-title" data-reveal>
        <h2 id="rm-standing-title">Where it stands</h2>
        <Standing detail={detail} />
      </section>}
      {story.checks && <section className="rm-checks" aria-labelledby="rm-checks-title" data-reveal>
        <h2 id="rm-checks-title">How it will be checked</h2>
        <p className="rm-section-note">From the acceptance criteria in the plan. Merged work still has to pass these on a release build.</p>
        <ul>{story.checks.map(check => <li key={check}>{check}</li>)}</ul>
        {story.checksNote && <p className="rm-section-note">{story.checksNote}</p>}
      </section>}
      {story.guardrails && <section className="rm-checks" aria-labelledby="rm-guard-title" data-reveal>
        <h2 id="rm-guard-title">What it won’t do</h2>
        <ul>{story.guardrails.map(rule => <li key={rule}>{rule}</li>)}</ul>
      </section>}
      <section className="rm-detail-work" aria-labelledby="rm-work-title">
        <h2 id="rm-work-title">{workTitle}</h2>
        {detail.items.map(item => <WorkEntry key={item.id} item={item} showPromise={detail.kind !== "version"} />)}
      </section>
      {(open.issues.length > 0 || open.pullRequests.length > 0) && <section className="rm-open" aria-labelledby="rm-open-title" data-reveal>
        <h2 id="rm-open-title">Open in the development repository</h2>
        <p className="rm-section-note">Titles as the developers wrote them, on {asOf}.</p>
        <ul>
          {open.issues.map(issue => <li key={issue.number}><a href={issue.url}><span>Issue {issue.number}</span>{issue.title}</a></li>)}
          {open.pullRequests.map(pull => <li key={pull.number}><a href={pull.url}><span>Pull request {pull.number}</span>{pull.title}</a></li>)}
        </ul>
      </section>}
      {showLinks && <section aria-labelledby="rm-links-title" data-reveal>
        <h2 id="rm-links-title">Around it</h2>
        <div className="rm-links">
          <PageLinks title="Builds on" list={buildsOn} />
          <PageLinks title="Leads to" list={leadsTo} />
        </div>
      </section>}
      {story.notIn && <section className="rm-checks" aria-labelledby="rm-notin-title" data-reveal>
        <h2 id="rm-notin-title">{detail.kind === "later" ? "Not on the roadmap at all" : "Not part of this"}</h2>
        <ul>{story.notIn.map(line => <li key={line}>{line}</li>)}</ul>
      </section>}
      <section className="rm-meanings" aria-labelledby="rm-meanings-title" data-reveal>
        <h2 id="rm-meanings-title">What the labels mean</h2>
        <dl>{statuses.map(status => <div key={status}><dt>{labels[status]}</dt><dd>{statusMeanings[status]}</dd></div>)}</dl>
      </section>
    </div>
    <nav className="rm-pager" aria-label="Along the roadmap">
      {previous ? <a href={detailHref(previous.name)} data-reveal><span>Before this</span><strong>{previous.title}</strong></a> : <span />}
      {next ? <a href={detailHref(next.name)} className="rm-pager-next" data-reveal><span>After this</span><strong>{next.title}</strong></a> : <a href="/roadmap/" className="rm-pager-next" data-reveal><span>Back to</span><strong>The whole roadmap</strong></a>}
    </nav>
  </main>
}
