import { useEffect, useMemo, useState, type ReactNode } from "react"
import { ALPHA_URL, GitHubLink, RELEASES_URL } from "./links"

export const DEMO_LIMIT = 12000
export const DEMO_SAMPLE = `# Field notes

A document can be both **readable source** and a considered rendered artifact.

## The working shape

- Keep the text close
- Reveal structure as needed
- Export only when useful

> Start with a sentence. See where it goes.

Try *emphasis*, **bold**, or \`inline code\`.`

// Deliberately small Markdown subset. No HTML parser, DOM insertion, URL
// attributes, network calls, or persistence. All authored strings are React text.
// The input cap and non-recursive parser also bound rendering work.
// Inline parsing intentionally scans left-to-right instead of using one broad
// backtracking expression: unfinished link/image syntax must stay cheap.
function inline(text: string): ReactNode[] {
  const parts: ReactNode[] = []
  let cursor = 0
  let plainStart = 0
  const flushPlain = (end: number) => {
    if (end > plainStart) parts.push(text.slice(plainStart, end))
  }
  while (cursor < text.length) {
    const marker = text[cursor]
    const isImage = marker === "!" && text[cursor + 1] === "["
    const isLink = marker === "["
    if (isImage || isLink) {
      const labelStart = cursor + (isImage ? 2 : 1)
      let scan = labelStart
      let labelEnd = -1
      while (scan < text.length && text[scan] !== "\n") {
        if (text[scan] === "]" && text[scan + 1] === "(") { labelEnd = scan; break }
        scan += 1
      }
      if (labelEnd !== -1) {
        scan = labelEnd + 2
        while (scan < text.length && text[scan] !== "\n" && text[scan] !== ")") scan += 1
        if (text[scan] === ")") {
          flushPlain(cursor)
          const label = text.slice(labelStart, labelEnd)
          parts.push(isImage
            ? <span key={cursor} className="demo-inert-image">[Image disabled: {label || "untitled"}]</span>
            : <span key={cursor} className="demo-inert-link" title="Links are inactive in this demo">{label}</span>)
          cursor = scan + 1
          plainStart = cursor
          continue
        }
      }
      // Treat an unterminated link/image run as literal once, rather than
      // restarting a search at every opening bracket.
      cursor = scan
      continue
    }
    const delimiter = marker === "`" ? "`" : marker === "*" ? (text[cursor + 1] === "*" ? "**" : "*") : ""
    if (delimiter) {
      const end = text.indexOf(delimiter, cursor + delimiter.length)
      if (end !== -1 && end > cursor + delimiter.length) {
        flushPlain(cursor)
        const content = text.slice(cursor + delimiter.length, end)
        parts.push(delimiter === "`"
          ? <code key={cursor}>{content}</code>
          : delimiter === "**" ? <strong key={cursor}>{content}</strong> : <em key={cursor}>{content}</em>)
        cursor = end + delimiter.length
        plainStart = cursor
        continue
      }
    }
    cursor += 1
  }
  flushPlain(text.length)
  return parts
}

export function MarkdownPreview({ source }: { source: string }) {
  const lines = source.slice(0, DEMO_LIMIT).replace(/\r\n?/g, "\n").split("\n")
  const blocks: ReactNode[] = []
  let index = 0
  const startsBlock = (line: string) => /^(#{1,6}\s|```|>\s?|[-*+]\s|\d+\.\s|---\s*$)/.test(line)
  while (index < lines.length) {
    const line = lines[index]
    const key = index++
    if (!line.trim()) continue
    if (line.startsWith("```")) {
      const code: string[] = []
      while (index < lines.length && !lines[index].startsWith("```")) code.push(lines[index++])
      if (index < lines.length) index++
      blocks.push(<pre key={key}><code>{code.join("\n")}</code></pre>)
      continue
    }
    const heading = /^(#{1,6})\s+(.+)$/.exec(line)
    if (heading) {
      // The preview is one labelled demo region inside a marketing page. Offset
      // authored headings so its sample document does not restart the page outline.
      const authoredLevel = heading[1].length
      const Heading = `h${Math.min(6, authoredLevel + 2)}` as "h3" | "h4" | "h5" | "h6"
      blocks.push(<Heading key={key} className={`demo-heading demo-heading-level-${authoredLevel}`}>{inline(heading[2])}</Heading>)
      continue
    }
    if (/^---\s*$/.test(line)) { blocks.push(<hr key={key} />); continue }
    if (/^>\s?/.test(line)) {
      const quote = [line.replace(/^>\s?/, "")]
      while (index < lines.length && /^>\s?/.test(lines[index])) quote.push(lines[index++].replace(/^>\s?/, ""))
      blocks.push(<blockquote key={key}>{inline(quote.join(" "))}</blockquote>)
      continue
    }
    const ordered = /^\d+\.\s/.test(line)
    const listPattern = ordered ? /^\d+\.\s+/ : /^[-*+]\s+/
    if (listPattern.test(line)) {
      const items = [line.replace(listPattern, "")]
      while (index < lines.length && listPattern.test(lines[index])) items.push(lines[index++].replace(listPattern, ""))
      const List = ordered ? "ol" : "ul"
      blocks.push(<List key={key}>{items.map((item, itemIndex) => <li key={itemIndex}>{inline(item)}</li>)}</List>)
      continue
    }
    const paragraph = [line]
    while (index < lines.length && lines[index].trim() && !startsBlock(lines[index])) paragraph.push(lines[index++])
    blocks.push(<p key={key}>{inline(paragraph.join(" "))}</p>)
  }
  return <>{blocks.length ? blocks : <p className="demo-empty">Your preview starts with your first word.</p>}</>
}

type DemoView = "split" | "source" | "preview"

const SAMPLE_ITEMS = ["Keep the text close", "Reveal structure as needed", "Export only when useful"]
const SAMPLE_BOLD = ["readable source", "bold"]
const hasNew = (matches: IterableIterator<RegExpMatchArray>, sample: string[]) => [...matches].some(match => !sample.includes(match[1].trim()))

// The guided try. Each step checks the text the visitor has written, so typing it and
// pressing "Show me" both count, in any order. A list item or bold run counts when it
// isn't one of the sample's own.
export const TOUR_STEPS: { title: string, hint: string, done: (source: string, view: DemoView) => boolean, show: (source: string) => string }[] = [
  {
    title: "Make it yours",
    hint: "Rewrite the first heading. Keep the # and the space before it.",
    done: source => { const heading = /^#[ \t]+(.+)$/m.exec(source); return !!heading && !["", "Field notes"].includes(heading[1].trim()) },
    show: source => /^#[ \t]+.*$/m.test(source) ? source.replace(/^#[ \t]+.*$/m, "# Project notes") : `# Project notes\n\n${source}`,
  },
  {
    title: "Add to the list",
    hint: "Start a new line under the list with a dash and a space.",
    done: source => hasNew(source.matchAll(/^[-*+][ \t]+(\S.*)$/gm), SAMPLE_ITEMS),
    show: source => {
      const lines = source.split("\n"); let last = -1
      lines.forEach((line, index) => { if (/^[-*+]\s+\S/.test(line)) last = index })
      if (last === -1) return `${source.trimEnd()}\n\n- Write it down first`
      lines.splice(last + 1, 0, "- Write it down first"); return lines.join("\n")
    },
  },
  {
    title: "Make a word bold",
    hint: "Wrap a word in two asterisks on each side, **like this**.",
    done: source => hasNew(source.matchAll(/\*\*([^*\n]+)\*\*/g), SAMPLE_BOLD),
    show: source => `${source.trimEnd()}\n\nThat part is **important**.`,
  },
  {
    title: "Read it back",
    hint: "Switch to Read to see only the rendered document.",
    done: (_source, view) => view === "preview",
    show: source => source,
  },
]

export default function MarkdownDemo() {
  const [source, setSource] = useState(DEMO_SAMPLE)
  const [view, setView] = useState<DemoView>("split")
  const [finished, setFinished] = useState(false)
  const preview = useMemo(() => <MarkdownPreview source={source} />, [source])
  const progress = TOUR_STEPS.map(step => step.done(source, view))
  const doneCount = progress.filter(Boolean).length
  const current = progress.indexOf(false)
  // Once every step has been done the end card stays, even if the visitor switches back to Both.
  useEffect(() => { if (current === -1) setFinished(true) }, [current])
  const ended = finished || current === -1
  const showMe = () => {
    if (current === -1) return
    if (current === TOUR_STEPS.length - 1) setView("preview")
    else setSource(TOUR_STEPS[current].show(source).slice(0, DEMO_LIMIT))
  }
  const restart = () => { setSource(DEMO_SAMPLE); setView("split"); setFinished(false) }
  return (
    <figure className="product-figure markdown-demo" aria-label="Live Markdown browser workflow demo">
      <div className="figure-toolbar">
        <div className="segmented" role="group" aria-label="Demo view">
          {(["split", "source", "preview"] as const).map(mode => <button key={mode} type="button" className={view === mode ? "active" : ""} aria-pressed={view === mode} onClick={() => setView(mode)}>{mode === "split" ? "Both" : mode === "source" ? "Write" : "Read"}</button>)}
        </div>
        <button className="demo-reset" type="button" onClick={restart}>Reset sample</button>
      </div>
      <div className="demo-intro"><span className="demo-live-dot" aria-hidden="true" />LIVE BROWSER DEMO <span>Browser only. Not the native Mac app.</span></div>
      {ended ? <section className="demo-tour demo-tour-done js-only" aria-labelledby="demo-tour-done-title">
        <div className="demo-tour-done-copy">
          <p className="demo-tour-kicker"><span aria-hidden="true">✓</span> Tour complete · 4 of 4</p>
          <h3 id="demo-tour-done-title">That’s the shape of it.</h3>
          <p>The Mac app keeps this side-by-side view and adds the heading outline, find and replace, diagrams, math and export.</p>
        </div>
        <div className="demo-tour-actions">
          <GitHubLink className="primary-link" href={ALPHA_URL}>Download the source alpha</GitHubLink>
          <p className="demo-tour-note">Source code only: you build it with Xcode 26 on macOS 26 and Apple Silicon, and it opens as MacDown 2. Signed downloads come later.</p>
          <div className="demo-tour-secondary"><GitHubLink className="text-link" href={RELEASES_URL}>Follow releases</GitHubLink><button type="button" className="demo-tour-link" onClick={restart}>Try again</button></div>
        </div>
      </section> : <section className="demo-tour js-only" aria-labelledby="demo-tour-title">
        <div className="demo-tour-head">
          <p className="demo-tour-kicker" id="demo-tour-title">Guided try · step {current + 1} of {TOUR_STEPS.length}</p>
          <button type="button" className="demo-tour-link" onClick={() => setFinished(true)}>Skip to download</button>
        </div>
        <ol className="demo-tour-steps">{TOUR_STEPS.map((step, index) => <li key={step.title} className={progress[index] ? "is-done" : index === current ? "is-current" : undefined} aria-current={index === current ? "step" : undefined}>
          <span className="demo-tour-mark" aria-hidden="true">{progress[index] ? "✓" : index + 1}</span>{step.title}<span className="demo-tour-sr">{progress[index] ? " (done)" : ""}</span>
        </li>)}</ol>
        <div className="demo-tour-task"><p><strong>{TOUR_STEPS[current].title}.</strong> {TOUR_STEPS[current].hint}</p><button type="button" className="demo-tour-show" onClick={showMe}>Show me</button></div>
      </section>}
      <p className="demo-tour-sr" aria-live="polite">{ended ? "Tour complete. Download the source alpha from the link in the demo." : doneCount ? `${doneCount} of ${TOUR_STEPS.length} steps done.` : ""}</p>
      <div className={`demo-panes demo-view-${view}`}>
        {view !== "preview" && <div className="demo-source-pane">
          <label htmlFor="demo-markdown-source">MARKDOWN / EDIT HERE</label>
          <textarea id="demo-markdown-source" aria-describedby="demo-scope demo-count" value={source} maxLength={DEMO_LIMIT} onChange={event => setSource(event.target.value.slice(0, DEMO_LIMIT))} spellCheck={false} autoComplete="off" autoCapitalize="off" />
        </div>}
        {view !== "source" && <div className="demo-preview-pane">
          <span className="demo-pane-label" id="demo-preview-label">PREVIEW / UPDATES AS YOU TYPE</span>
          <div className="demo-preview" role="region" aria-labelledby="demo-preview-label" tabIndex={0}>{preview}</div>
        </div>}
      </div>
      <p className="no-js-only demo-no-js">The live preview needs JavaScript. The sample above shows how it renders.</p>
      <div className="demo-status"><span>This demo does not save or send your text.</span><span id="demo-count">{source.length.toLocaleString("en-US")} / 12,000</span></div>
      <figcaption id="demo-scope">Browser workflow demo, not the native Mac app.<span>Basic Markdown: headings, lists, quotes, code, bold and emphasis. HTML stays text; links and images are inactive.</span></figcaption>
    </figure>
  )
}
