import { useMemo, useState, type ReactNode } from "react"

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

export default function MarkdownDemo() {
  const [source, setSource] = useState(DEMO_SAMPLE)
  const [view, setView] = useState<"split" | "source" | "preview">("split")
  const preview = useMemo(() => <MarkdownPreview source={source} />, [source])
  return (
    <figure className="product-figure markdown-demo" aria-label="Live Markdown browser workflow demo">
      <div className="figure-toolbar">
        <div className="segmented" role="group" aria-label="Demo view">
          {(["split", "source", "preview"] as const).map(mode => <button key={mode} type="button" className={view === mode ? "active" : ""} aria-pressed={view === mode} onClick={() => setView(mode)}>{mode === "split" ? "Both" : mode === "source" ? "Write" : "Read"}</button>)}
        </div>
        <button className="demo-reset" type="button" onClick={() => setSource(DEMO_SAMPLE)}>Reset sample</button>
      </div>
      <div className="demo-intro"><span className="demo-live-dot" aria-hidden="true" />LIVE BROWSER DEMO <span>Browser only. Not the native Mac app.</span></div>
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
