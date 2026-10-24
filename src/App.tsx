import { useEffect, useState } from "react"
import Roadmap from "./Roadmap"
import TryLine from "./MarkdownDemo"
import Capabilities from "./Capabilities"
import data from "./roadmap-data.json"
import { ALPHA_URL, GitHubLink, GitHubMark, ISSUES_URL, RELEASES_URL, SITE_SOURCE_URL, SOURCE_URL } from "./links"
import { isRoadmapPage, isRoadmapRoute, routeFromLocation, stageOf } from "./route"

const navItems = [
  ["Try it", "/#try"],
  ["Features", "/#features"],
  ["Roadmap", "/roadmap/"],
  ["FAQ", "/#faq"],
] as const

// The hero's reel: crops of one real capture of the development build. The frame
// sits inside the headline; with JavaScript and motion allowed, the reel advances as
// the hero is scrolled (the stage is sticky; nothing captures the wheel).
const ORIGINAL = "mostlytext-development-editor-preview.png"
const reel = [
  { caption: "The Markdown source, with line numbers.", src: "mostlytext-development-editor-preview-tablet", widths: [960, 1640], width: 1640, height: 1093, position: "left top",
    alt: "Actual MostlyText development build: the Markdown source pane with line numbers and syntax highlighting." },
  { caption: "The page it makes, beside it.", src: "mostlytext-development-editor-preview-hero", widths: [960, 1600, 2448], width: 2448, height: 1200, position: "right top",
    alt: "Actual MostlyText development build: the rendered preview pane, with a heading, a checklist and a code block." },
  { caption: "One window, source and page together.", src: "mostlytext-development-editor-preview-hero", widths: [960, 1600, 2448], width: 2448, height: 1200, position: "center", whole: true,
    alt: "Actual MostlyText development build: the whole window, Markdown source on the left and its live preview on the right." },
]

const faqs = [
  ["Can I download MostlyText now?", "A source-only testing alpha is available with build instructions. There is no prebuilt app, DMG or CLI binary yet. Your build is unsigned and still named MacDown 2; signed MostlyText copies are planned for later through the App Store and direct download."],
  ["Which Macs does it run on?", "The verified build instructions need macOS 26 or later, Apple Silicon, Xcode 26 and XcodeGen. Final compatibility is set by each release, so check the release notes for the build you use."],
  ["Why does it open as MacDown 2?", "MostlyText descends from MacDown, and the development app and its repository still carry the MacDown 2 name. The rename to MostlyText, with its own icon and settings migration, is on the roadmap before 1.0."],
  ["What files does it work with?", "Markdown first, plus plain text, HTML, JSON, YAML, TOML and several code formats in the current format registry. That list is development evidence, not a final support matrix."],
  ["Do I need to import my documents?", "No. A file stays a file in the folder or repository where it already lives. Open it from Finder, or from the folder sidebar."],
  ["Where do I ask for help or report a problem?", "Read the release notes first, then use the repository's issues page for reproducible problems. No response time is promised."],
  ["Is it open source?", "The source is public in the MacDown 2 repository. Check its current licence and third-party notices there; final distribution terms are still subject to release review."],
] as const

// The roadmap's own groups, summarised as rows: the group on the left, its state on the right.
const groupRows = [
  { title: "Write, find and organise", ids: ["E01", "E02", "E03", "E04", "E05", "E08", "E09", "E10", "E11", "E13", "E18", "E22"] },
  { title: "Explain the technical work", ids: ["E06", "E07", "E12", "E14", "E19", "E20", "E21", "anchors", "resource-security"] },
  { title: "Feel at home on a Mac", ids: ["E15", "E23", "safety", "E16"] },
  { title: "MacDown 2 becomes MostlyText", ids: ["identity", "E17-software", "cutover", "launch-surface", "commercial-direction"] },
  { title: "A verified release", ids: ["E00", "S", "V1", "sources", "RC2", "gate115", "release"] },
]
const laterRows = [
  { title: "Make everyday work better", value: "1.0.x to 1.4" },
  { title: "Richer ways to work", value: "1.5 to 1.10" },
  { title: "Let real workflows lead", value: "No version yet" },
]
function stateOf(ids: string[]) {
  const items = ids.map(id => data.upToOne.find(item => item.id === id)).filter(Boolean) as typeof data.upToOne
  const done = items.filter(item => item.status === "implemented").length
  return done === items.length ? `All ${items.length} merged` : done ? `${done} of ${items.length} merged` : `${items.length} still ahead`
}
const implemented = data.upToOne.filter(item => item.status === "implemented").length
const releaseGroup = ["E00", "S", "V1", "sources", "RC2", "gate115", "release"].map(id => data.upToOne.find(item => item.id === id)).filter(Boolean) as typeof data.upToOne
const epicIndexUrl = `${data.implementationRepository}/blob/${data.sourceHead}/planning/epics/README.md`
const asOf = new Date(`${data.asOf}T12:00:00Z`).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" })

function BrandLockup() {
  return <img className="brand-lockup" src="/brand/mostlytext-lockup.svg" width="146" height="24" alt="" />
}

function Reel() {
  return <div className="reel" aria-roledescription="carousel" aria-label="The development build">
    <div className="reel-track">
      {reel.map((frame, index) => <figure className={`reel-frame${index === 0 ? " is-on" : ""}${frame.whole ? " is-whole" : ""}`} key={frame.caption} aria-hidden={index === 0 ? undefined : true}>
        <a href={`/images/${ORIGINAL}`} target="_blank" rel="noopener noreferrer" tabIndex={index === 0 ? undefined : -1} aria-label="Open the full-size capture of the development build (opens in a new tab)">
          <picture>
            <source type="image/webp" sizes="(min-width: 62rem) 50vw, calc(100vw - 2rem)" srcSet={frame.widths.map(width => `/images/${frame.src}-${width}.webp ${width}w`).join(", ")} />
            <img src={`/images/${ORIGINAL}`} width={frame.width} height={frame.height} style={{ objectPosition: frame.position }} loading={index === 0 ? "eager" : "lazy"} fetchPriority={index === 0 ? "high" : "auto"} decoding="async" alt={frame.alt} />
          </picture>
        </a>
      </figure>)}
    </div>
  </div>
}

function ReelCaption() {
  return <p className="reel-caption"><span className="reel-text">{reel[0].caption}</span> <span className="reel-count">1 of {reel.length}</span></p>
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
    // The menu is a compact-width overlay (index.css, 47.5rem); widening the window dismisses it.
    const compact = window.matchMedia("(max-width: 47.5rem)")
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

  useEffect(() => {
    // Entrances: each part arrives once as it nears the viewport. Everything is visible
    // without JavaScript, under reduced motion, and if the observer never runs.
    const parts = [...document.querySelectorAll<HTMLElement>("[data-reveal]")]
    const io = "IntersectionObserver" in window ? new IntersectionObserver(entries => {
      for (const entry of entries) if (entry.isIntersecting) { entry.target.classList.add("is-in"); io?.unobserve(entry.target) }
    }, { rootMargin: "0px 0px -12% 0px", threshold: 0.05 }) : null
    const watch = (part: Element) => io ? io.observe(part) : part.classList.add("is-in")
    parts.forEach(watch)
    // Parts that mount later (a roadmap chapter coming back after a search) arrive the same way.
    const added = new MutationObserver(() => document.querySelectorAll("[data-reveal]:not(.is-in)").forEach(watch))
    added.observe(document.getElementById("root") ?? document.body, { childList: true, subtree: true })
    document.documentElement.classList.add("reveals")

    // The hero reel follows the scroll position through the sticky hero.
    const hero = document.querySelector<HTMLElement>(".hero")
    const track = hero?.querySelector<HTMLElement>(".reel-track")
    const frames = [...(hero?.querySelectorAll<HTMLElement>(".reel-frame") ?? [])]
    const text = hero?.querySelector(".reel-text"), count = hero?.querySelector(".reel-count")
    const still = window.matchMedia("(prefers-reduced-motion: reduce)"), wide = window.matchMedia("(min-width: 62rem)")
    let frame = 0, shown = 0
    const update = () => {
      frame = 0
      if (!hero || !track || !frames.length) return
      const moving = wide.matches && !still.matches
      hero.classList.toggle("is-pinned", moving)
      let index = 0
      if (moving) {
        const travel = hero.offsetHeight - window.innerHeight
        const progress = travel > 0 ? Math.min(1, Math.max(0, -hero.getBoundingClientRect().top / travel)) : 0
        const step = frames[1] ? frames[1].offsetTop - frames[0].offsetTop : 0
        track.style.transform = `translate3d(0, ${(-progress * (frames.length - 1) * step).toFixed(1)}px, 0)`
        index = Math.min(frames.length - 1, Math.round(progress * (frames.length - 1)))
      } else track.style.transform = ""
      if (index !== shown) {
        shown = index
        frames.forEach((el, k) => { el.classList.toggle("is-on", k === index); el.toggleAttribute("aria-hidden", k !== index); el.querySelector("a")?.setAttribute("tabindex", k === index ? "0" : "-1") })
        if (text) text.textContent = reel[index].caption
        if (count) count.textContent = `${index + 1} of ${reel.length}`
      }
    }
    const request = () => { if (!frame) frame = requestAnimationFrame(update) }
    window.addEventListener("scroll", request, { passive: true })
    window.addEventListener("resize", request)
    still.addEventListener("change", request); wide.addEventListener("change", request)
    update()
    return () => {
      io?.disconnect(); added.disconnect(); if (frame) cancelAnimationFrame(frame)
      window.removeEventListener("scroll", request); window.removeEventListener("resize", request)
      still.removeEventListener("change", request); wide.removeEventListener("change", request)
    }
  }, [isRoadmap, route])

  return (
    <div className="site-shell">
      <a className="skip-link" href="#main-content" onClick={event => { if (isRoadmap) { event.preventDefault(); document.getElementById("main-content")?.focus(); window.scrollTo({ top: 0, behavior: "auto" }) } }}>Skip to content</a>
      <header className="site-header">
        <a className="brand" href="/#home" aria-label="MostlyText home" onClick={() => setMenuOpen(false)}><BrandLockup /></a>
        <button className="menu-button" type="button" aria-expanded={menuOpen} aria-controls="primary-navigation" onClick={() => setMenuOpen(current => !current)}>{menuOpen ? "Close" : "Menu"}</button>
        <nav id="primary-navigation" className={menuOpen ? "nav-open" : ""} aria-label="Primary navigation">
          {navItems.map(([label, href]) => <a key={href} href={href} onClick={() => setMenuOpen(false)}>{label}</a>)}
          <a className="button nav-action" href={ALPHA_URL} onClick={() => setMenuOpen(false)}><span className="link-label"><GitHubMark />Build the alpha from source</span></a>
        </nav>
      </header>
      {isRoadmap ? <Roadmap stage={stageOf(route)} roadmapPage={onRoadmapPage} /> : <main id="main-content" tabIndex={-1}>
        <section className="hero" id="home" aria-labelledby="hero-title">
          <div className="hero-stage">
            <h1 id="hero-title" className="hero-half hero-first">A text editor,<span className="visually-hidden"> mostly.</span></h1>
            <p className="hero-half hero-second" aria-hidden="true">mostly.</p>
            <Reel />
            <ReelCaption />
            <p className="hero-lede">For the note, the README, the idea that needs room. A native Mac editor for text and Markdown, with more there when you need it.</p>
            <div className="hero-cta">
              <div className="hero-actions">
                <GitHubLink className="button" href={ALPHA_URL}>Build the alpha from source</GitHubLink>
                <a className="text-link" href="#try">Try it in your browser</a>
              </div>
              <p className="hero-note">No ready-to-install app yet. Use copies of documents while testing.</p>
            </div>
          </div>
        </section>

        <section className="origin" id="origin" aria-labelledby="origin-title">
          <div className="origin-copy" data-reveal>
            <h2 id="origin-title">Where it began</h2>
            <p className="origin-first">MostlyText began with MacDown’s side-by-side layout: Markdown on the left, the page it makes on the right.</p>
            <p>When MacDown was retired, I wanted to keep that shape and give it a more native Mac feel.</p>
            <p>The file stays a Markdown file, in the folder or repository where it already lives. Open it from Finder, or press Command-P and type part of its name.</p>
            <p>The heading outline sits beside it, so a long README becomes a list of places to go. <a href="/roadmap/">See what’s planned</a>.</p>
          </div>
          <figure className="origin-picture" data-reveal>
            <a href="/images/mostlytext-development-workspace.png" target="_blank" rel="noopener noreferrer" aria-label="Open the full-size capture of the development build workspace (opens in a new tab)">
              <picture>
                <source type="image/webp" sizes="(min-width: 62rem) 56vw, calc(100vw - 2rem)" srcSet={[960, 1600, 2624].map(width => `/images/mostlytext-development-workspace-${width}.webp ${width}w`).join(", ")} />
                <img src="/images/mostlytext-development-workspace.png" width="2624" height="1928" loading="lazy" decoding="async" alt="Actual MostlyText development build with a folder sidebar, heading outline, Markdown editor and live preview." />
              </picture>
            </a>
            <figcaption>The development build: folders, the heading outline, the source and its preview. It is ahead of the published alpha and may change.</figcaption>
          </figure>
        </section>

        <section className="try-section" id="try" aria-labelledby="try-title">
          <h2 id="try-title" data-reveal>Type a line of Markdown</h2>
          <TryLine />
        </section>

        <section className="features" id="features" aria-labelledby="features-title">
          <Capabilities />
        </section>

        <section className="plan" id="roadmap" aria-labelledby="plan-title">
          <div className="plan-figure" data-reveal><p><strong>{implemented} of {data.upToOne.length}</strong></p><p>work areas in the 1.0 plan are merged, not yet verified for release.</p></div>
          <div className="plan-column">
            <h2 id="plan-title" data-reveal>What works, what’s next</h2>
            <p className="plan-note" data-reveal>The 37 are every work area in the 1.0 plan, including the {releaseGroup.length} release steps, of which {releaseGroup.filter(item => item.status === "implemented").length} is done. Counted from the <a href={epicIndexUrl}>epic index and release records at commit {data.sourceHead.slice(0, 7)}</a>, a snapshot of {asOf}; later work isn’t reconciled yet. “Merged” is the Implemented status in those records.</p>
            <p className="plan-group" data-reveal>To 1.0</p>
            <ul className="plan-rows">{groupRows.map(row => <li key={row.title} data-reveal><span>{row.title}</span><span>{stateOf(row.ids)}</span></li>)}</ul>
            <p className="plan-group" data-reveal>After 1.0</p>
            <ul className="plan-rows">{laterRows.map(row => <li key={row.title} data-reveal><span>{row.title}</span><span>{row.value}</span></li>)}</ul>
            <a className="text-link plan-link" href="/roadmap/" data-reveal>The full roadmap</a>
          </div>
        </section>

        <section className="faq" id="faq" aria-labelledby="faq-title">
          <h2 id="faq-title">Questions</h2>
          <div className="faq-list">{faqs.map(([question, answer]) => <details key={question} name="mostlytext-faq" data-reveal><summary>{question}<i aria-hidden="true" /></summary><p>{answer}</p></details>)}</div>
        </section>

        <section className="release" id="release-status" aria-labelledby="release-title">
          <h2 id="release-title" data-reveal>The alpha is ready to build.</h2>
          <div className="release-body" data-reveal>
            <p>Version 0.1.0-alpha.1 is source code with build instructions: macOS 26 or later, Apple Silicon, Xcode 26 and XcodeGen. Your build is unsigned and opens as MacDown 2. Signed downloads come later, and 1.0 is still ahead.</p>
            <p className="release-warning">No ready-to-install app yet. Use copies of documents while testing.</p>
            <div className="release-actions">
              <GitHubLink className="button" href={ALPHA_URL}>Build the alpha from source</GitHubLink>
              <a className="text-link" href={ISSUES_URL}>Open issues</a>
              <a className="text-link" href={SITE_SOURCE_URL}>Website source</a>
            </div>
          </div>
        </section>
      </main>}
      <footer className="site-footer">
        <p>A text editor, mostly.</p>
        <p className="footer-links"><a href={RELEASES_URL}>Releases</a><a href={ISSUES_URL}>Issues</a><a href={SOURCE_URL}>Source</a></p>
        <p>Descended from MacDown. Licence and notices in the repository.</p>
      </footer>
    </div>
  )
}
