import { useEffect, useState } from "react"
import Roadmap from "./Roadmap"
import MarkdownDemo from "./MarkdownDemo"
import { isRoadmapPage, isRoadmapRoute, routeFromLocation, stageOf } from "./route"

import { ALPHA_URL, GitHubLink, ISSUES_URL, RELEASES_URL, SITE_SOURCE_URL, SOURCE_URL } from "./links"

const navItems = [
  ["Home", "/#home"],
  ["Features", "/#features"],
  ["Try it", "/#demo"],
  ["Roadmap", "/roadmap/"],
  ["FAQ", "/#faq"],
  ["Release status", "/#release-status"],
] as const

const workflowSteps = [
  ["01", "Find the file in your head.", "Open from the active folder, or use Cmd-P Quick Open when you remember part of a filename. Keep the heading outline nearby for the section you need."],
  ["02", "Make the change twelve times.", "Use literal find and replace for a product name, a regular expression for a pattern, or multiple cursors for repeated edits. Folder search-and-replace reaches beyond the current document."],
  ["03", "Keep the details deliberate.", "Choose encodings and line endings. Show line numbers and invisibles. Use built-in or scoped snippets for text you keep writing. These capabilities are in the current development build."],
] as const

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

function RouteArrow() {
  return <span aria-hidden="true">→</span>
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

// WebP sizes are generated from the original captures; the hero file is a crop of
// the editor-and-preview capture with its empty lower canvas removed.
const screenshots = {
  hero: {
    original: "mostlytext-development-editor-preview.png",
    stem: "mostlytext-development-editor-preview-hero", widths: [960, 1600, 2448], width: 2448, height: 1200,
    description: "Actual MostlyText development build: Markdown source with line numbers on the left and its live preview on the right.",
    note: "Cropped from a capture that is ahead of the published alpha; the interface may change. Select the image to view the full capture.",
    // The whole window is only readable from about 75rem up. Narrower screens get
    // tighter crops of the same capture: tablets and small laptops the source
    // pane and the start of the preview, phones the window's top-left corner.
    tablet: { stem: "mostlytext-development-editor-preview-tablet", widths: [960, 1640] },
    phone: { stem: "mostlytext-development-editor-preview-phone", widths: [400, 800],
      note: "Cropped to the Markdown source; the full capture shows the live preview beside it. It is ahead of the published alpha. Select the image to view it." },
  },
  workspace: {
    original: "mostlytext-development-workspace.png",
    stem: "mostlytext-development-workspace", widths: [960, 1600, 2624], width: 2624, height: 1928,
    description: "Actual MostlyText development build with a folder sidebar, heading outline, Markdown editor, and live preview, with correctly aligned line-number gutters.",
    note: "This capture is ahead of the published alpha, and the interface may change. Select the image to view it full size.",
  },
} as const

function NativeAppScreenshot({ variant }: { variant: keyof typeof screenshots }) {
  const shot = screenshots[variant]
  const hero = variant === "hero"
  return (
    <figure className={`workflow-figure native-app-figure${hero ? " native-app-figure-hero" : ""}`}>
      <a className="native-app-image-link" href={`/images/${shot.original}`} target="_blank" rel="noopener noreferrer" aria-label="Open the full-size MostlyText development-build screenshot (opens in a new tab)">
        <picture>
          {"phone" in shot && <source media="(max-width: 44rem)" type="image/webp" sizes="calc(100vw - 2rem)"
            srcSet={shot.phone.widths.map(width => `/images/${shot.phone.stem}-${width}.webp ${width}w`).join(", ")} />}
          {"tablet" in shot && <source media="(max-width: 75rem)" type="image/webp" sizes="(min-width: 62rem) calc(100vw - 3rem), calc(100vw - 2.5rem)"
            srcSet={shot.tablet.widths.map(width => `/images/${shot.tablet.stem}-${width}.webp ${width}w`).join(", ")} />}
          <source type="image/webp" srcSet={shot.widths.map(width => `/images/${shot.stem}-${width}.webp ${width}w`).join(", ")}
            sizes={hero ? "(min-width: 62rem) min(100vw - 3rem, 87.5rem), (min-width: 44rem) min(100vw - 2.5rem, 60rem), calc(100vw - 2rem)" : "(min-width: 62rem) min(100vw - 3rem, 87.5rem), 100vw"} />
          <img src={`/images/${shot.original}`} width={shot.width} height={shot.height} loading={hero ? "eager" : "lazy"} fetchPriority={hero ? "high" : "auto"} decoding={hero ? "auto" : "async"} alt={shot.description} />
        </picture>
      </a>
      <figcaption>
        Actual MostlyText development build.
        <span className={"phone" in shot ? "caption-wide" : undefined}>{shot.note}</span>
        {"phone" in shot && <span className="caption-phone">{shot.phone.note}</span>}
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

function FeatureCards() {
  return <div className="feature-ledger">{featureCards.map(([number, meta, title, text]) =>
    <article className="feature-entry" key={number}>
      <span className="entry-number">{number}</span>
      <div><p className="entry-meta">{meta}</p><h3>{title}</h3><p>{text}</p></div>
    </article>
  )}</div>
}

export default function App({ initialRoute, roadmapPage }: { initialRoute?: string; roadmapPage?: boolean }) {
  // The build prerenders each page with an explicit route (scripts/prerender.mjs).
  const [route, setRoute] = useState(() => initialRoute ?? routeFromLocation())
  const [onRoadmapPage] = useState(() => roadmapPage ?? isRoadmapPage())
  const isRoadmap = isRoadmapRoute(route)
  const [menuOpen, setMenuOpen] = useState(false)

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
    if (!menuOpen) return
    // Disclosure navigation: the panel closes once focus or a pointer leaves the
    // header, so it never covers whatever has focus on the page below.
    const header = document.querySelector(".site-header")
    const closeOutside = (event: FocusEvent | PointerEvent) => {
      const target = (event instanceof FocusEvent ? event.relatedTarget : event.target) as Node | null
      if (event instanceof FocusEvent && !target) return
      if (!header?.contains(target)) setMenuOpen(false)
    }
    header?.addEventListener("focusout", closeOutside as EventListener)
    document.addEventListener("pointerdown", closeOutside as EventListener)
    return () => {
      header?.removeEventListener("focusout", closeOutside as EventListener)
      document.removeEventListener("pointerdown", closeOutside as EventListener)
    }
  }, [menuOpen])

  useEffect(() => {
    // The menu is a compact-width overlay (index.css, 44rem); widening the window dismisses it.
    const compact = window.matchMedia("(max-width: 44rem)")
    const close = () => { if (!compact.matches) setMenuOpen(false) }
    compact.addEventListener("change", close)
    return () => compact.removeEventListener("change", close)
  }, [])

  useEffect(() => {
    const navigate = () => { setRoute(routeFromLocation()); setMenuOpen(false) }
    window.addEventListener("hashchange", navigate)
    return () => window.removeEventListener("hashchange", navigate)
  }, [])
  useEffect(() => {
    document.documentElement.classList.toggle("roadmap-route", isRoadmap)
    document.title = isRoadmap ? "Roadmap — MostlyText" : "MostlyText — A text editor, mostly."
    requestAnimationFrame(() => {
      if (isRoadmap) window.scrollTo({ top: 0, behavior: "auto" })
      else if (route) document.getElementById(route.slice(1))?.scrollIntoView({ behavior: "auto" })
    })
  }, [route, isRoadmap])

  return (
    <div className="site-shell">
      <a className="skip-link" href="#main-content" onClick={event => { if (isRoadmap) { event.preventDefault(); document.getElementById("main-content")?.focus(); window.scrollTo({ top: 0, behavior: "auto" }) } }}>Skip to content</a>
      <header className="site-header">
        <a className="brand" href="/#home" aria-label="MostlyText home" onClick={() => setMenuOpen(false)}>
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
      {isRoadmap ? <Roadmap stage={stageOf(route)} roadmapPage={onRoadmapPage} /> : <main id="main-content" tabIndex={-1}>
        <section className="hero section-frame" id="home">
          <div className="hero-copy">
            <p className="eyebrow"><span />Native macOS editor · active prerelease</p>
            <h1>A text editor, <em>mostly.</em></h1>
            <div className="hero-lede">
              <p className="hero-support">For the note, the README, the idea that needs room. A native Mac editor for text and Markdown, with more there when you need it.</p>
              <div className="hero-actions">
                <GitHubLink className="primary-link" href={ALPHA_URL}>Build the source alpha</GitHubLink>
                <a className="text-link" href="#demo">Try it in your browser <span aria-hidden="true">↓</span></a>
              </div>
              <p className="hero-release-note">Source-only, unsigned build. Verified instructions: macOS 26+, Apple Silicon, Xcode 26, and XcodeGen. It still opens as MacDown 2.</p>
            </div>
          </div>
          <div className="hero-visual"><NativeAppScreenshot variant="hero" /></div>
        </section>

        <section className="features section-frame screen-panel split-panel" id="features">
          <header className="section-heading">
            <p className="section-number">01 / Capabilities</p>
            <h2>For the files around the code.</h2>
            <p>Work on a README without opening your whole development setup. Write, read, and make precise changes, and keep the diagram and the export beside the explanation.</p>
          </header>
          <FeatureCards />
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
        </section>
        <section className="browser-demo section-frame screen-panel split-panel" id="demo" aria-labelledby="demo-title">
          <header className="section-heading">
            <p className="section-number">03 / Try it</p>
            <h2 id="demo-title">Try the shape of a document.</h2>
            <p>A small, local Markdown preview for trying the workflow in a browser. It is separate from the native Mac app and never saves or sends your text.</p>
          </header>
          <div className="browser-demo-stage"><MarkdownDemo /></div>
        </section>

        <section className="workflow screen-panel split-panel" id="developers">
          <div className="section-frame">
            <header className="section-heading workflow-heading">
              <p className="section-number">04 / Developer workflow</p>
              <h2>For the part of coding that is mostly explaining.</h2>
              <p>The README somebody finds at 11pm. The setup note that outlives the setup. The design note that needs one diagram.</p>
            </header>
            <div className="workflow-visual snap-subpanel"><NativeAppScreenshot variant="workspace" /></div>
            <div className="workflow-steps">{workflowSteps.map(([number, title, text]) =>
              <article className="snap-subpanel" key={number}><span>{number}</span><div><h3>{title}</h3><p>{text}</p></div></article>
            )}</div>
          </div>
        </section>

        <section className="roadmap section-frame screen-panel split-panel" id="roadmap">
          <header className="section-heading">
            <p className="section-number">05 / Roadmap</p><h2>What works. What’s next.</h2>
            <p>The full plan, from today’s development work to 1.0 and the ideas held for later. Evidence checked 15 October 2026.</p>
          </header>
          <div className="roadmap-grid">{roadmap.map(([number, title, text]) =>
            <article className="snap-subpanel" key={number}><span className="entry-number">{number}</span><h3>{title}</h3><p>{text}</p></article>
          )}</div>
          <a className="primary-link roadmap-source" href="/roadmap/">Explore the full roadmap <RouteArrow /></a>
        </section>

        <section className="faq-section screen-panel" id="faq">
          <div className="section-frame faq-layout">
            <header className="section-heading"><p className="section-number">06 / FAQ</p><h2>Questions worth answering plainly.</h2><p>Start with repository releases and issues for current project facts.</p></header>
            <div className="faq-list">{faqs.map(([question, answer], index) => <details key={question} name="mostlytext-faq"><summary><span>{String(index + 1).padStart(2, "0")}</span>{question}<i aria-hidden="true" /></summary><p>{answer}</p></details>)}</div>
          </div>
        </section>

        <section className="release section-frame screen-panel" id="release-status">
          <div className="release-status-line"><span className="status-dot" /><p>SOURCE-ONLY ALPHA</p><span>v0.1.0-alpha.1</span></div>
          <div className="release-grid">
            <div><p className="section-number">07 / Release status</p><h2>An alpha you can build.</h2></div>
            <div className="release-copy"><p>The source-only testing alpha is available with self-build instructions. No prebuilt app, DMG, or CLI binary is included.</p><p>Verified build instructions require macOS 26 or later, Apple Silicon, Xcode 26, and XcodeGen. The local build is unsigned and still named MacDown 2. Signed MostlyText copies are planned for later through the App Store and direct distribution; stable 1.0 is still ahead.</p><p>The app and this website are both on GitHub. The app repository is still named <code>macdown_2</code>, after its development lineage.</p><div className="release-links"><GitHubLink className="primary-link" href={ALPHA_URL}>Build the source alpha</GitHubLink><GitHubLink className="text-link" href={ISSUES_URL}>View open issues</GitHubLink><GitHubLink className="text-link" href={SITE_SOURCE_URL}>Website source</GitHubLink></div></div>
          </div>
        </section>
      </main>}
      <footer><div className="section-frame footer-grid">
        <div className="footer-brand"><a className="brand" href="/#home" aria-label="MostlyText home"><BrandLockup /></a><p>For text, and what comes after.</p></div>
        <div className="footer-links"><GitHubLink href={RELEASES_URL}>Release status</GitHubLink><GitHubLink href={ISSUES_URL}>Report an issue</GitHubLink><GitHubLink href={SOURCE_URL}>Project &amp; source</GitHubLink></div>
        <div className="footer-legal"><p>Descended from MacDown. Built with a more native Mac feel.</p><p>Consult the repository for current licence and third-party notices. Final distribution terms remain subject to release review.</p></div>
        <p className="footer-end">NATIVE macOS TEXT EDITOR / PRERELEASE</p>
      </div></footer>
    </div>
  )
}
