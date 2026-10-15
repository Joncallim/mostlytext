import { useEffect, useState, type ReactNode } from "react"
import Roadmap from "./Roadmap"
import MarkdownDemo from "./MarkdownDemo"

const ALPHA_URL = "https://github.com/Joncallim/macdown_2/releases/tag/v0.1.0-alpha.1"
const RELEASES_URL = "https://github.com/Joncallim/macdown_2/releases"
const ISSUES_URL = "https://github.com/Joncallim/macdown_2/issues"
const SOURCE_URL = "https://github.com/Joncallim/macdown_2#readme"
const SITE_SOURCE_URL = "https://github.com/Joncallim/mostlytext"

const navItems = [
  ["Home", "#home"],
  ["Features", "#features"],
  ["Roadmap", "#/roadmap"],
  ["Guide", "#guide"],
  ["FAQ", "#faq"],
  ["Release status", "#release-status"],
] as const

const pageSections = [
  ["home", "Home"],
  ["features", "Capabilities"],
  ["render-share", "Render & share"],
  ["origin", "Where it began"],
  ["demo", "Browser demo"],
  ["developers", "Developer workflow"],
  ["editing-tools", "Editing tools"],
  ["roadmap", "Roadmap"],
  ["guide", "Field guide"],
  ["faq", "FAQ"],
  ["release-status", "Release status"],
] as const

const workflowSteps = [
  ["01", "Find the file in your head.", "Open from the active folder, or use Cmd-P Quick Open when you remember part of a filename. Keep the heading outline nearby for the section you need."],
  ["02", "Make the change twelve times.", "Use literal find and replace for a product name, a regular expression for a pattern, or multiple cursors for repeated edits. Folder search-and-replace reaches beyond the current document."],
  ["03", "Keep the details deliberate.", "Choose encodings and line endings. Show line numbers and invisibles. Use built-in or scoped snippets for text you keep writing. These capabilities are in the current development build."],
] as const

const guideSections = [
  {
    id: "getting-started",
    marker: "01",
    title: "Getting started",
    text: "Start from the file, not a project wizard. Open a document from Finder or navigate to it from a folder. Choose a light or dark theme, then arrange the source, outline, and preview for the work at hand.",
    note: "The project is prerelease software. Check release notes before depending on a particular workflow.",
  },
  {
    id: "readme-docs",
    marker: "02",
    title: "Authoring README files and docs",
    text: "Use syntax-highlighted Markdown source for precise edits and the heading outline to move through longer technical documents. Preview the rendered hierarchy beside the source, and use editing assists for common Markdown structures.",
    note: "Literal and regular-expression replacement are available for targeted or repeated changes.",
  },
  {
    id: "structured-notes",
    marker: "03",
    title: "Structured notes",
    text: "Keep notes as ordinary text files and use headings as durable structure. File navigation supports a folder-based practice without requiring a proprietary notebook or database.",
    note: "MostlyText also works with plain text, JSON, and HTML when the work extends beyond Markdown.",
  },
  {
    id: "diagrams-math",
    marker: "04",
    title: "Diagrams and math",
    text: "Write inline or display math directly in the document. The implementation includes Mermaid and D2 preview paths, Graphviz export rendering, and math scanning and rendering. Renderer and theme behavior still need release validation.",
    note: "Rendering support is an implemented development capability, not a statement that final release gates have passed.",
  },
  {
    id: "export",
    marker: "05",
    title: "Export",
    text: "Choose HTML for a browser, self-contained HTML when you need a bundled document, or PDF for a fixed artifact. Keep the original source alongside anything you export.",
    note: "Self-contained export cannot embed authored raw HTML; unresolved image paths need attention. Release samples and exact behavior are still pending.",
  },
]

const faqs = [
  [
    "Can I download MostlyText now?",
    "A source-only testing alpha is available with self-build instructions. There is no prebuilt app, DMG, or CLI binary. Your local build is unsigned and still named MacDown 2; signed MostlyText copies are planned for later through the App Store and direct distribution.",
  ],
  [
    "Which macOS versions are supported?",
    "The project targets macOS 26 or later. Final compatibility is confirmed only with a release, so consult the release notes for the requirements attached to a specific build.",
  ],
  [
    "What file types does it work with?",
    "The current format registry includes Markdown, plain text, HTML, JSON, YAML, TOML, and several code formats. This is development evidence, not a final support matrix.",
  ],
  [
    "Where should I ask for help or report a problem?",
    "Review the release notes first, then use the repository issues page to report reproducible problems or add relevant technical context. No response time is promised.",
  ],
  [
    "Is MostlyText open source?",
    "The project source is available in the MacDown 2 repository. Consult its current licence and third-party notices; final distribution terms are still subject to release review.",
  ],
] as const

function BrandLockup() {
  return <img className="brand-lockup" src="/brand/mostlytext-lockup.svg" alt="" />
}

function ExternalArrow() {
  return <span aria-hidden="true">↗︎</span>
}

function DocumentMotif({ label }: { label: string }) {
  return <div className="document-motif" aria-hidden="true">
    <span className="document-motif-mark">¶</span>
    <span className="document-motif-line" />
    <span>{label}</span>
  </div>
}

function OriginComic() {
  const panels = [
    ["A familiar split", "A small editor window, source on one side and preview on the other."],
    ["A native-feeling wish", "The old tool retires; the desk stays ready for the next note."],
    ["MostlyText", "A fresh, native Mac editor for the files that explain the work."],
  ] as const
  return <figure className="origin-comic" aria-labelledby="origin-comic-caption">
    <div className="origin-comic-panels">
      {panels.map(([caption, description], index) => <article className="origin-comic-panel" key={caption}>
        <svg viewBox="0 0 240 154" role="img" aria-label={description}>
          <rect x="1" y="1" width="238" height="152" rx="4" className="comic-frame" />
          <circle cx="30" cy="24" r="5" className="comic-dot" /><circle cx="47" cy="24" r="5" className="comic-dot" /><circle cx="64" cy="24" r="5" className="comic-dot" />
          {index === 0 && <><rect x="25" y="42" width="190" height="82" rx="3" className="comic-window" /><path d="M39 58h60M39 70h37M39 82h52" className="comic-lines" /><path d="M132 59h57M132 73h43M132 87h52M132 101h34" className="comic-preview-lines" /><path d="M119 43v80" className="comic-divider" /></>}
          {index === 1 && <><path d="M38 115h164" className="comic-desk" /><rect x="93" y="55" width="64" height="47" rx="3" className="comic-window comic-window-muted" /><path d="M102 67h46M102 78h30" className="comic-lines" /><circle cx="72" cy="91" r="16" className="comic-head" /><path d="M60 113c4-15 20-15 25 0" className="comic-person" /><path d="M177 48c10 0 17 7 17 16s-7 16-17 16h-9l-8 8 2-12c-3-3-4-7-4-12 0-9 8-16 19-16Z" className="comic-bubble" /><path d="M169 64h16" className="comic-lines" /></>}
          {index === 2 && <><path d="M33 115h174" className="comic-desk" /><rect x="62" y="47" width="118" height="66" rx="4" className="comic-window comic-window-blue" /><path d="M77 64h37M77 76h60M77 88h45" className="comic-lines-light" /><path d="M125 48v64" className="comic-divider-light" /><circle cx="46" cy="105" r="13" className="comic-head" /><path d="M35 121c4-13 17-13 22 0" className="comic-person" /><path d="M187 61l5 9 10 2-8 7 2 10-9-5-9 5 2-10-8-7 10-2 5-9Z" className="comic-spark" /></>}
        </svg>
        <p>{caption}</p>
      </article>)}
    </div>
    <figcaption id="origin-comic-caption">A small origin story: familiar split view, a wish for something native, then MostlyText.</figcaption>
  </figure>
}

function NextSection({ destination }: { destination: readonly [string, string] }) {
  return <a className="section-advance" href={`#${destination[0]}`} aria-label={`Next section: ${destination[1]}`}>
    <span>Next section</span><strong>{destination[1]}</strong><i aria-hidden="true">↓</i>
  </a>
}

function NativeAppScreenshot({ focused = false, priority = false }: { focused?: boolean; priority?: boolean }) {
  const image = focused ? "mostlytext-development-editor-preview.png" : "mostlytext-development-workspace.png"
  const description = focused
    ? "Actual MostlyText development build focused on the Markdown editor and live preview, with correctly aligned line-number gutters."
    : "Actual MostlyText development build with a folder sidebar, heading outline, Markdown editor, and live preview, with correctly aligned line-number gutters."
  return (
    <figure className={`workflow-figure native-app-figure${focused ? " native-app-figure-focused" : ""}${priority ? " native-app-figure-hero" : ""}`}>
      <a className="native-app-image-link" href={`/images/${image}`} target="_blank" rel="noopener noreferrer" aria-label="Open the full-size MostlyText development-build screenshot">
        <img src={`/images/${image}`} width={2624} height={1928} loading={priority ? "eager" : "lazy"} fetchPriority={priority ? "high" : "auto"} decoding="async" alt={description} />
      </a>
      <figcaption>
        Actual MostlyText development build.
        <span>This is ahead of the published alpha, and the interface may change. Select the image to view it full size.</span>
      </figcaption>
    </figure>
  )
}

const featureCards = [
  ["A", "WRITE / READ", "Keep the page beside the source.", "Write Markdown with syntax highlighting, read its rendered form alongside it, and use headings to jump through longer documents. Files stay in their existing folders and repositories."],
  ["B", "FIND / CHANGE", "A name changed. Everywhere.", "Correct a word with literal find and replace. Match a pattern with regular expressions. Use multiple cursors or folder search-and-replace when the change goes beyond one place."],
  ["C", "DIAGRAMS / MATH", "That box needs an arrow.", "Keep Mermaid, D2, or Graphviz source beside the explanation. Development renderer paths include Mermaid and D2 preview, Graphviz export, and inline and display math."],
  ["D", "EXPORT / SHARE", "Please send a PDF.", "HTML for a browser. PDF for a fixed artifact. Self-contained HTML is also in development, with limits: authored raw HTML cannot be embedded, and unresolved image paths need attention. Keep the Markdown alongside the export."],
] as const

const roadmap = [
  ["01", "In development", "A native editor, source and preview, precise text tools, diagrams, and export. Implemented work is still subject to release verification."],
  ["02", "To macOS 1.0", "Finish editor hardening, themes and Finder integration, accessibility and localisation, then verify the signed release and update path."],
  ["03", "After 1.0", "A chapter-by-chapter direction through 1.10: better tables, linked editing, local history, workspaces, and publishing. Later exploration stays clearly labelled."],
] as const

function FeatureCards({ start, end, children }: { start: number; end: number; children: ReactNode }) {
  return <div className="feature-ledger capability-pages">{featureCards.slice(start, end).map(([number, meta, title, text], index) =>
    <div className="capability-page" key={number}>{index === 0 && children}<article className="feature-entry snap-subpanel" key={number}>
      <span className="entry-number">{number}</span>
      <div><p className="entry-meta">{meta}</p><h3>{title}</h3><p>{text}</p></div>
    </article></div>
  )}</div>
}

export default function App() {
  const [route, setRoute] = useState(window.location.hash)
  const isRoadmap = route.startsWith("#/roadmap")
  const [menuOpen, setMenuOpen] = useState(false)
  const [guideIndex, setGuideIndex] = useState(0)
  const activeGuide = guideSections[guideIndex]

  useEffect(() => {
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setMenuOpen(false)
        if (document.activeElement?.closest("#primary-navigation")) {
          document.querySelector<HTMLButtonElement>(".menu-button")?.focus()
        }
      }
    }
    window.addEventListener("keydown", closeOnEscape)
    return () => window.removeEventListener("keydown", closeOnEscape)
  }, [])

  useEffect(() => {
    const navigate = () => { setRoute(window.location.hash); setMenuOpen(false) }
    window.addEventListener("hashchange", navigate)
    return () => window.removeEventListener("hashchange", navigate)
  }, [])
  useEffect(() => {
    document.documentElement.classList.toggle("roadmap-route", isRoadmap)
    document.title = isRoadmap ? "Roadmap — MostlyText" : "MostlyText — A text editor. Mostly."
    requestAnimationFrame(() => {
      if (isRoadmap) window.scrollTo({ top: 0, behavior: "instant" })
      else if (route) document.getElementById(route.slice(1))?.scrollIntoView({ behavior: "instant" })
    })
  }, [route, isRoadmap])

  const guideControls = <><button type="button" onClick={() => setGuideIndex((guideIndex + guideSections.length - 1) % guideSections.length)}>← Previous</button><span>{guideIndex + 1} / {guideSections.length}</span><button type="button" onClick={() => setGuideIndex((guideIndex + 1) % guideSections.length)}>Next →</button></>

  return (
    <div className="site-shell">
      <a className="skip-link" href="#main-content" onClick={event => { if (isRoadmap) { event.preventDefault(); document.getElementById("main-content")?.focus(); window.scrollTo({ top: 0, behavior: "instant" }) } }}>Skip to content</a>
      <header className="site-header">
        <a className="brand" href="#home" aria-label="MostlyText home" onClick={() => setMenuOpen(false)}>
          <BrandLockup /><small>for macOS</small>
        </a>
        <button className="menu-button" type="button" aria-expanded={menuOpen} aria-controls="primary-navigation"
          aria-label={menuOpen ? "Close navigation" : "Open navigation"} onClick={() => setMenuOpen(current => !current)}>
          <span className={`menu-icon ${menuOpen ? "is-open" : ""}`} aria-hidden="true"><span /><span /></span>
        </button>
        <nav id="primary-navigation" className={menuOpen ? "nav-open" : ""} aria-label="Primary navigation">
          {navItems.map(([label, href]) => <a key={href} href={href} onClick={() => setMenuOpen(false)}>{label}</a>)}
        </nav>
      </header>
      {isRoadmap ? <Roadmap route={route} /> : <main id="main-content" tabIndex={-1}>
        <section className="hero section-frame" id="home">
          <div className="hero-copy snap-subpanel">
            <p className="eyebrow"><span />Native macOS editor · active prerelease</p>
            <h1>A text editor. <em>Mostly.</em></h1>
            <p className="hero-support">For the note, the README, the idea that needs room. A native Mac editor for text and Markdown, with more there when you need it.</p>
            <div className="hero-actions">
              <a className="primary-link" href={ALPHA_URL}>Build the alpha <span aria-hidden="true">→</span></a>
              <a className="text-link" href="#roadmap">See the roadmap <span aria-hidden="true">↓</span></a>
            </div>
            <DocumentMotif label="A place for the next thought" />
          </div>
          <div className="hero-visual snap-subpanel"><NativeAppScreenshot priority /></div>
          <div className="hero-index" aria-hidden="true"><span>MT—01</span><span>TEXT / MARKDOWN / SOURCE</span></div>
          <NextSection destination={pageSections[1]} />
        </section>

        <section className="features section-frame screen-panel split-panel" id="features">
          <FeatureCards start={0} end={2}>
          <header className="section-heading">
            <p className="section-number">01 / Capabilities</p>
            <h2>For the files around the code.</h2>
            <p>Work on a README without opening your whole development setup. Write, read, and make precise changes in one place.</p>
          </header>
          </FeatureCards>
          <NextSection destination={pageSections[2]} />
        </section>
        <section className="features section-frame screen-panel split-panel" id="render-share" aria-labelledby="render-title">
          <FeatureCards start={2} end={4}>
          <header className="section-heading">
            <p className="section-number">01 / Render &amp; share</p>
            <h2 id="render-title">A little more than words.</h2>
            <p>The explanation and its diagram belong together. Keep the source; make a rendered artifact when someone needs one.</p>
          </header>
          </FeatureCards>
          <NextSection destination={pageSections[3]} />
        </section>

        <section className="intro-strip screen-panel" id="origin">
          <div className="section-frame origin-grid">
            <div><p className="section-number">02 / Where it began</p><h2>Built for the files that explain the work.</h2></div>
            <div className="origin-copy">
              <p>I liked MacDown’s simple, side-by-side layout. When it was retired, I wanted to keep that approach and give it a more native Mac feel. That’s where MostlyText began.</p>
              <p>Keep the source, rendered preview, and heading outline close together. Write in Markdown, check how it reads, and move straight to the section you need.</p>
              <p>The file remains a Markdown file in the repository or folder where it already lives.</p>
            </div>
            <OriginComic />
          </div>
          <NextSection destination={pageSections[4]} />
        </section>
        <section className="browser-demo section-frame screen-panel split-panel" id="demo" aria-labelledby="demo-title">
          <header className="section-heading">
            <p className="section-number">03 / Browser demo</p>
            <h2 id="demo-title">Try the shape of a document.</h2>
            <p>A small, local Markdown preview for trying the workflow in a browser. It is separate from the native Mac app and never saves or sends your text.</p>
          </header>
          <div className="browser-demo-stage"><MarkdownDemo /></div>
          <NextSection destination={pageSections[5]} />
        </section>

        <section className="workflow screen-panel split-panel" id="developers">
          <div className="section-frame">
            <header className="section-heading workflow-heading">
              <p className="section-number">04 / Developer workflow</p>
              <h2>For the part of coding that is mostly explaining.</h2>
              <p>The README somebody finds at 11pm. The setup note that outlives the setup. The design note that needs one diagram.</p>
            </header>
            <div className="workflow-visual snap-subpanel"><NativeAppScreenshot /></div>
          </div>
          <NextSection destination={pageSections[6]} />
        </section>
        <section className="workflow screen-panel split-panel" id="editing-tools" aria-labelledby="editing-title">
          <div className="section-frame">
            <header className="section-heading workflow-heading">
              <p className="section-number">04 / Editing tools</p>
              <h2 id="editing-title">Small edits. Precise tools.</h2>
              <p>Document-first work, with the controls that matter when the text is part of a repository.</p>
            </header>
            <div className="workflow-steps">{workflowSteps.map(([number, title, text]) =>
              <article className="snap-subpanel" key={number}><span>{number}</span><div><h3>{title}</h3><p>{text}</p></div></article>
            )}</div>
            <div className="workflow-visual workflow-visual-focused snap-subpanel"><NativeAppScreenshot focused /></div>
          </div>
          <NextSection destination={pageSections[7]} />
        </section>

        <section className="roadmap section-frame screen-panel split-panel" id="roadmap">
          <header className="section-heading">
            <p className="section-number">05 / Roadmap</p><h2>What works. What’s next.</h2>
            <p>The full plan, from today’s development work to 1.0 and the ideas held for later. Evidence checked 15 October 2026.</p>
          </header>
          <div className="roadmap-grid">{roadmap.map(([number, title, text]) =>
            <article className="snap-subpanel" key={number}><span className="entry-number">{number}</span><h3>{title}</h3><p>{text}</p></article>
          )}</div>
          <a className="primary-link roadmap-source" href="#/roadmap">Explore the full roadmap <ExternalArrow /></a>
          <NextSection destination={pageSections[8]} />
        </section>

        <section className="guide section-frame screen-panel" id="guide">
          <header className="section-heading guide-heading">
            <p className="section-number">06 / Field guide</p><h2>Start with the task at hand.</h2>
            <p>Choose a path through the current development capabilities.</p>
          </header>
          <div className="guide-layout">
            <nav className="guide-nav" aria-label="Choose a guide topic"><p>IN THIS GUIDE</p>
              {guideSections.map((item, index) => <button key={item.id} type="button" aria-pressed={guideIndex === index} aria-controls="guide-detail" onClick={() => setGuideIndex(index)}><span>{item.marker}</span>{item.title}</button>)}
            </nav>
            <div className="guide-content" id="guide-detail" aria-live="polite" aria-atomic="true">
              <article>
                <div className="guide-body"><span className="guide-marker">{activeGuide.marker}</span><div><h3>{activeGuide.title}</h3><p>{activeGuide.text}</p></div><div className="guide-controls mobile-guide-controls">{guideControls}</div></div>
                <div className="guide-note"><p className="mobile-guide-note-label">{activeGuide.title} · Note</p><aside>{activeGuide.note}</aside><div className="guide-controls mobile-guide-controls">{guideControls}</div></div>
              </article>
              <div className="guide-controls desktop-guide-controls">{guideControls}</div>
            </div>
          </div>
          <NextSection destination={pageSections[9]} />
        </section>

        <section className="faq-section screen-panel" id="faq">
          <div className="section-frame faq-layout">
            <header className="section-heading"><p className="section-number">07 / FAQ</p><h2>Questions worth answering plainly.</h2><p>Start with repository releases and issues for current project facts.</p></header>
            <div className="faq-list">{faqs.map(([question, answer], index) => <details key={question} name="mostlytext-faq"><summary><span>{String(index + 1).padStart(2, "0")}</span>{question}<i aria-hidden="true" /></summary><p>{answer}</p></details>)}</div>
          </div>
          <NextSection destination={pageSections[10]} />
        </section>

        <section className="release section-frame screen-panel" id="release-status">
          <div className="release-status-line"><span className="status-dot" /><p>SOURCE-ONLY ALPHA</p><span>v0.1.0-alpha.1</span></div>
          <div className="release-grid">
            <div><p className="section-number">08 / Release status</p><h2>An alpha you can build.</h2></div>
            <div className="release-copy"><p>The source-only testing alpha is available with self-build instructions. No prebuilt app, DMG, or CLI binary is included.</p><p>Targeting macOS 26 or later, the local build is unsigned and still named MacDown 2. Signed MostlyText copies are planned for later through the App Store and direct distribution; stable 1.0 is still ahead.</p><div className="release-links"><a className="primary-link" href={ALPHA_URL}>Build the alpha <ExternalArrow /></a><a className="text-link" href={ISSUES_URL}>View open issues <ExternalArrow /></a></div></div>
          </div>
        </section>
        <aside className="github-banner section-frame" aria-labelledby="github-banner-title">
          <div>
            <p className="section-number">Source &amp; development</p>
            <h2 id="github-banner-title">MostlyText is on GitHub.</h2>
            <p>Read the website source, or follow the native app’s development in its public repository.</p>
          </div>
          <div className="github-banner-actions">
            <a className="primary-link" href={SITE_SOURCE_URL}>Website source <ExternalArrow /></a>
            <a className="text-link" href={SOURCE_URL}>Native app source <ExternalArrow /></a>
          </div>
        </aside>
      </main>}
      <footer><div className="section-frame footer-grid">
        <div className="footer-brand"><a className="brand" href="#home" aria-label="MostlyText home"><BrandLockup /></a><p>For text, and what comes after.</p></div>
        <div className="footer-links"><a href={RELEASES_URL}>Release status <ExternalArrow /></a><a href={ISSUES_URL}>Report an issue <ExternalArrow /></a><a href={SOURCE_URL}>Project &amp; source <ExternalArrow /></a></div>
        <div className="footer-legal"><p>Descended from MacDown. Built with a more native Mac feel.</p><p>Consult the repository for current licence and third-party notices. Final distribution terms remain subject to release review.</p></div>
        <p className="footer-end">NATIVE macOS TEXT EDITOR / PRERELEASE</p>
      </div></footer>
    </div>
  )
}
