import { useState } from "react"
import { MarkdownPreview } from "./MarkdownDemo"

type View = "source" | "both" | "page"
type Output = "editor" | "html" | "pdf"
type Settings = { view: View; name: string; diagram: boolean; dark: boolean; output: Output }
const START: Settings = { view: "both", name: "", diagram: false, dark: false, output: "editor" }
const FIND = "MacDown 2"

const SOURCE = `# Release notes

MacDown 2 keeps your Markdown as it is.

## Before you build

- Install Xcode 26
- Run XcodeGen, then open MacDown 2

\`\`\`mermaid
graph LR
  Write --> Preview --> Export
\`\`\``

// The flow the Mermaid block describes, drawn the way a rendered preview shows it.
function Diagram() {
  const boxes = ["Write", "Preview", "Export"]
  return <svg className="cap-diagram" viewBox="0 0 300 64" role="img" aria-label="Rendered diagram: Write, then Preview, then Export">
    {boxes.map((label, index) => <g key={label} transform={`translate(${index * 104} 12)`}>
      <rect width="88" height="40" rx="6" />
      <text x="44" y="25" textAnchor="middle">{label}</text>
      {index < 2 && <path d="M90 20h12m-5-4 5 4-5 4" />}
    </g>)}
  </svg>
}

function SourcePane({ text }: { text: string }) {
  return <pre className="cap-source" aria-label="Markdown source">{text.split("\n").map((line, index) => {
    const kind = /^#{1,6} /.test(line) ? "h" : /^[-*] /.test(line) ? "li" : /^```/.test(line) ? "fence" : ""
    return <span key={index} className={kind ? `md-${kind}` : undefined}>{line || " "}{"\n"}</span>
  })}</pre>
}

function PagePane({ text, diagram }: { text: string; diagram: boolean }) {
  const [before] = text.split("```mermaid")
  return <div className="cap-page" aria-label="Rendered page">
    <MarkdownPreview source={diagram ? before : text} />
    {diagram && <Diagram />}
  </div>
}

function Segmented<T extends string>({ label, value, options, onChange }: { label: string; value: T; options: [T, string][]; onChange: (value: T) => void }) {
  return <div className="segmented" role="radiogroup" aria-label={label}>
    {options.map(([key, text]) => <button key={key} type="button" role="radio" aria-checked={value === key} onClick={() => onChange(key)}>{text}</button>)}
  </div>
}

export default function Capabilities() {
  const [s, setS] = useState<Settings>(START)
  const set = (patch: Partial<Settings>) => setS(current => ({ ...current, ...patch }))
  const name = s.name.trim()
  const text = name ? SOURCE.split(FIND).join(name) : SOURCE
  const replaced = name ? SOURCE.split(FIND).length - 1 : 0
  const file = s.output === "html" ? "Release notes.html" : s.output === "pdf" ? "Release notes.pdf" : "README.md"
  const blocks = [
    {
      title: "Source and page, side by side.",
      text: "Write Markdown with syntax highlighting and read the rendered page beside it. Headings become an outline you can jump through.",
      control: <Segmented label="View" value={s.view} options={[["source", "Source"], ["both", "Both"], ["page", "Page"]]} onChange={view => set({ view, output: "editor" })} />,
    },
    {
      title: "A name changed. Everywhere.",
      text: "Literal find and replace, regular expressions, multiple cursors, and search and replace across a folder.",
      control: <label className="field">Replace “{FIND}” with<input type="text" value={s.name} maxLength={24} placeholder="MostlyText" onChange={event => set({ name: event.target.value, output: "editor" })} /><span className="field-note" aria-live="polite">{replaced ? `${replaced} replaced` : `${SOURCE.split(FIND).length - 1} matches`}</span></label>,
    },
    {
      title: "That box needs an arrow.",
      text: "Keep Mermaid, D2 or Graphviz source beside the explanation. Diagram and math rendering are in the development build.",
      control: <label className="toggle"><input type="checkbox" checked={s.diagram} onChange={event => set({ diagram: event.target.checked, view: s.view === "source" ? "both" : s.view, output: "editor" })} /><span>Render the diagram</span></label>,
    },
    {
      title: "Light or dark.",
      text: "Light and dark themes for the editor and the preview, so a long night with a README is easier on the eyes.",
      control: <Segmented label="Theme" value={s.dark ? "dark" : "light"} options={[["light", "Light"], ["dark", "Dark"]]} onChange={value => set({ dark: value === "dark", output: "editor" })} />,
    },
    {
      title: "Please send a PDF.",
      text: "Export HTML for a browser or PDF for a fixed copy, and keep the Markdown beside it. Self-contained HTML is in development, with limits.",
      control: <Segmented label="Show as" value={s.output} options={[["editor", "Editor"], ["html", "HTML"], ["pdf", "PDF"]]} onChange={output => set({ output })} />,
    },
  ]
  return <div className="caps">
    <div className="caps-stage">
      <figure className="caps-output" aria-label="Browser illustration of the editor's output">
        <div className={`cap-window${s.dark ? " is-dark" : ""} is-${s.output === "editor" ? s.view : s.output}`} data-ui>
          <p className="cap-title">{file}</p>
          {s.output === "editor"
            ? <div className="cap-panes">{s.view !== "page" && <SourcePane text={text} />}{s.view !== "source" && <PagePane text={text} diagram={s.diagram} />}</div>
            : <div className="cap-export"><PagePane text={text} diagram={s.diagram} /></div>}
        </div>
        <figcaption>A browser illustration of what the app does on your Mac. Change it with the controls.</figcaption>
      </figure>
    </div>
    <div className="caps-list">
      <h2 id="features-title">More when you need it</h2>
      {blocks.map(block => <div className="cap" key={block.title}>
        <h3>{block.title}</h3>
        <p>{block.text}</p>
        <div className="cap-control js-only">{block.control}</div>
      </div>)}
      <button type="button" className="text-button js-only" onClick={() => setS(START)}>Reset the example</button>
    </div>
  </div>
}
