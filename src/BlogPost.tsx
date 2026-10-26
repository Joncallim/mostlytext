import { ALPHA_URL, GitHubLink } from "./links"

const FEEDBACK_URL = "https://github.com/Joncallim/macdown_2/issues/new?template=alpha-feedback.yml"

export default function BlogPost() {
  return <main id="main-content" className="blog-post" tabIndex={-1}>
    <article>
      <header className="blog-header">
        <h1>Rebuilding MacDown as a native Mac app</h1>
        <p className="blog-byline">Jonathan, developer of MostlyText · 26 October 2026</p>
        <p className="blog-intro">Keep the Markdown file. Keep the preview beside it. Rebuild the Mac app around that simple workflow.</p>
      </header>

      <aside className="blog-status" aria-label="Source alpha status">
        <p><strong>Source alpha: v0.1.0-alpha.1.</strong> Build it yourself with macOS 26 or later, Xcode 26 and XcodeGen. The release commands are verified on Apple Silicon. There is no prebuilt app download; local builds are unsigned and have no automatic updates. Use copies of documents while testing.</p>
        <p><a href={ALPHA_URL}>Source-alpha release and build instructions</a> · <a href={FEEDBACK_URL}>Report alpha feedback</a></p>
      </aside>

      <div className="blog-copy">
        <p>What I wanted to keep from MacDown was straightforward: write Markdown on the left, read the result on the right, and leave the document as an ordinary file. MostlyText is an open-source, MIT-licensed fork and successor of <a href="https://github.com/MacDownApp/macdown">MacDown</a>, rebuilt in Swift for macOS 26. The app still opens as “MacDown 2”.</p>

        <h2>One document, two views</h2>
        <p>Take a small set of release notes. The heading, list and code fence belong to the Markdown file; the preview shows how they read together. The outline gives those headings a second job: click one to move to that part of the document.</p>
        <p>The editor uses an AppKit text view backed by TextKit 2, with Tree-sitter syntax highlighting. Markdown prose is rendered in a native SwiftUI preview using Textual. I want the editing surface to feel at home on the Mac without making the file depend on MostlyText.</p>

        <figure className="blog-figure">
          <a href="/images/blog/markdown-source-preview.webp" aria-label="Open the full-size Markdown source and preview screenshot">
            <picture>
              <source media="(max-width: 40rem)" srcSet="/images/blog/markdown-preview-phone.webp" width="900" height="680" />
              <img src="/images/blog/markdown-source-preview.webp" width="1930" height="680" alt="Release notes with rendered headings and lists, including Plain files and Native preview. Open full size to compare the Markdown source and preview." decoding="async" />
            </picture>
          </a>
          <figcaption>Release notes in two views. Still from private development build <code>9f360cfa</code>, still named MacDown 2; this is not the public alpha tag or a signed release. <a href="/images/blog/markdown-source-preview.webp">Open full size</a>.</figcaption>
        </figure>

        <h2>Change the text, check the diagram</h2>
        <p>The same document can contain a Mermaid fence. In this example I changed <code>Write</code> to <code>Draft</code> in the diagram source, and the preview redrew the first box. The diagram stays with the explanation in the same Markdown file.</p>
        <p>The Markdown prose uses native text rendering; Mermaid diagrams are generated locally from bundled scripts in offscreen WebKit views. No remote diagram-rendering service is involved.</p>

        <figure className="blog-figure">
          <a href="/images/blog/mermaid-preview.webp" aria-label="Open the full-size Mermaid diagram screenshot">
            <img src="/images/blog/mermaid-preview.webp" width="900" height="290" alt="Under How a document moves, a rendered Mermaid diagram connects three boxes: Draft, Preview and Export." loading="lazy" decoding="async" />
          </a>
          <figcaption>The diagram after changing <code>Write</code> to <code>Draft</code> in its source. Still from private development build <code>9f360cfa</code>, still named MacDown 2; this is not the public alpha tag or a signed release. <a href="/images/blog/mermaid-preview.webp">Open full size</a>.</figcaption>
        </figure>

        <h2>What I need from the alpha</h2>
        <p>These screenshots show a private development build, not a promise that the public alpha has passed every release check. Larger Markdown files remain a <a href="https://github.com/Joncallim/macdown_2/issues/203">responsiveness problem</a>, and <a href="https://github.com/Joncallim/macdown_2/issues/459">syntax-highlighting correctness</a> is still under investigation. There is no date for 1.0; the <a href="/roadmap/">roadmap</a> separates current work from later plans.</p>
        <p>If you can build the alpha, try a copy of a document you know well. Does its preview match what you expect? Does editing or moving through it become slow? <a href={FEEDBACK_URL}>Send a report through the alpha feedback form</a> with the build tag or commit, your Mac model, macOS and Xcode versions, what happened and what you expected. A small synthetic example helps; please leave personal documents and secrets out.</p>
        <p>If you cannot build it yet, <a href="https://github.com/Joncallim/macdown_2">watch the repository</a> using <strong>Watch → Custom → Releases</strong>. Thanks to Tzu-ping Chung and the MacDown contributors for the app this work grows from.</p>
      </div>

      <aside className="blog-callout" aria-label="Build and test the source alpha">
        <h2>Build it. Try your files. Tell me what breaks.</h2>
        <p>The source-alpha release has the exact build commands and known limitations. Use copies of documents while testing.</p>
        <div className="release-actions"><GitHubLink className="button" href={ALPHA_URL}>Build the alpha from source</GitHubLink><a className="text-link" href={FEEDBACK_URL}>Report alpha feedback</a></div>
      </aside>
    </article>
  </main>
}
