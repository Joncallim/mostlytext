import { useState, type ReactNode } from "react"
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

// The live thing: a heading you can type into. Each line of Markdown renders at once
// underneath; trying a heading, a list item and some emphasis ends in the download prompt.
export type LineKind = "heading" | "list" | "emphasis"
export function kindOf(line: string): LineKind | null {
  if (/^#{1,6}[ \t]+\S/.test(line)) return "heading"
  if (/^([-*+]|\d+\.)[ \t]+\S/.test(line)) return "list"
  if (/\*\*[^*\n]+\*\*|\*[^*\n]+\*|`[^`\n]+`/.test(line)) return "emphasis"
  return null
}
export const TRY_KINDS: { kind: LineKind, name: string, example: string }[] = [
  { kind: "heading", name: "a heading", example: "## Ship it on Friday" },
  { kind: "list", name: "a list item", example: "- Write the README first" },
  { kind: "emphasis", name: "some bold", example: "Keep it **mostly** text" },
]
export const TRY_START = "# Release notes"

export default function TryLine() {
  const [line, setLine] = useState(TRY_START)
  const [tried, setTried] = useState<LineKind[]>([])
  const [finished, setFinished] = useState(false)
  const take = (value: string) => {
    const next = value.replace(/[\r\n]+/g, " ").slice(0, 160)
    setLine(next)
    const kind = kindOf(next)
    if (kind && !tried.includes(kind)) {
      const all = [...tried, kind]
      setTried(all)
      if (all.length === TRY_KINDS.length) setFinished(true)
    }
  }
  const restart = () => { setLine(TRY_START); setTried([]); setFinished(false) }
  const left = TRY_KINDS.filter(item => !tried.includes(item.kind))
  const progress = tried.length === 0
    ? "Change the line, or pick an example. Try a heading, a list item and some bold."
    : `${tried.length} of ${TRY_KINDS.length} tried. Next, ${left.map(item => item.name).join(" or ")}.`
  return <div className="try">
    <label className="try-label" htmlFor="try-line">Your line of Markdown</label>
    <div className="try-input" data-ui>
      <input id="try-line" value={line} onChange={event => take(event.target.value)} spellCheck={false} autoComplete="off" autoCapitalize="off" maxLength={160} aria-describedby="try-progress" />
    </div>
    <div className="try-answer" data-ui>
      <p className="try-file">notes.md</p>
      <div className="try-page" aria-live="polite" aria-label="Rendered line">
        <MarkdownPreview source={line} />
      </div>
    </div>
    {finished ? <div className="try-end js-only">
      <h3>That’s the shape of it.</h3>
      <p>The Mac app keeps the source beside the page, with the heading outline, find and replace, diagrams, math and export.</p>
      <div className="try-actions">
        <GitHubLink className="button" href={ALPHA_URL}>Get the alpha</GitHubLink>
        <button type="button" className="text-button" onClick={restart}>Try again</button>
      </div>
      <p className="try-note">Source code only: you build it with Xcode 26 on macOS 26 and Apple Silicon, and it opens as MacDown 2. Signed downloads come later. <a href={RELEASES_URL}>Follow releases</a>.</p>
    </div> : <div className="try-more js-only">
      <p className="try-progress" id="try-progress">{progress}</p>
      <div className="try-examples">
        {TRY_KINDS.map(item => <button type="button" key={item.kind} className={tried.includes(item.kind) ? "is-done" : undefined} aria-pressed={tried.includes(item.kind)} onClick={() => take(item.example)}><code>{item.example}</code></button>)}
      </div>
      <button type="button" className="text-button" onClick={() => setFinished(true)}>Skip to the download</button>
    </div>}
    <p className="no-js-only try-no-js">The live preview needs JavaScript. Without it, this shows how the starting line renders.</p>
  </div>
}
