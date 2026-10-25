import { ALPHA_URL, GitHubLink, ISSUES_URL, RELEASES_URL } from "./links"

export default function BlogPost() {
  return <main id="main-content" className="blog-post" tabIndex={-1}>
    <article>
      <header className="blog-header">
        <p className="blog-kicker">Notes from MostlyText</p>
        <h1>Rebuilding MacDown as a native Mac app</h1>
        <p className="blog-intro">MostlyText continues MacDown’s source-and-preview workflow in a new native implementation.</p>
      </header>

      <div className="blog-copy">
        <p>MacDown was many people’s first Markdown editor on the Mac: free, open source, source on the left and preview on the right. So I started again.</p>
        <p>MostlyText is an open-source, MIT-licensed fork and successor of MacDown, rewritten in Swift for macOS 26. A source alpha is out now, and I’m looking for people to build it, break it and tell me. The app still opens as “MacDown 2” for now; the rename comes later, for reasons I’ll get to.</p>

        <h2>What it is</h2>
        <p>A text editor, mostly. The development build works with plain Markdown files and includes:</p>
        <ul>
          <li>a native editor with Tree-sitter syntax highlighting and themes;</li>
          <li>a native preview, beside the source or on its own, that scrolls with you;</li>
          <li>Mermaid, D2 and Graphviz diagrams rendered locally on your Mac, plus equation support that is still being verified;</li>
          <li>HTML and PDF export from the same renderer as the preview; and</li>
          <li>a heading outline, a folder sidebar, and list-continuing and bracket-pairing assists.</li>
        </ul>
        <p>No account, no cloud, no proprietary format. Your files stay files.</p>

        <h2>The decisions that mattered</h2>
        <h3>A real text view, not a text field</h3>
        <p>I chose a custom <code>NSTextView</code> on TextKit 2 for the editor. It gives the project a native text-system foundation rather than treating the document as a simple text field. Large-file responsiveness still needs work; I’m not making a speed comparison with MacDown here.</p>

        <h3>Incremental highlighting, still in progress</h3>
        <p>MostlyText uses Tree-sitter through SwiftTreeSitter, which supports incremental parsing. That does not make large-file performance a solved problem.</p>
        <p>Large Markdown files remain an active responsiveness issue (<a href="https://github.com/Joncallim/macdown_2/issues/203">#203</a>), and highlighting correctness is tracked separately in <a href="https://github.com/Joncallim/macdown_2/issues/459">#459</a>. <a href="https://github.com/Joncallim/macdown_2/pull/472">PR #472</a> is closed and records historical measurements and an experiment, not a current performance guarantee or proof that the underlying problems are resolved. The public alpha excludes that experimental background-reparse work.</p>

        <h3>A preview with no web page in it</h3>
        <p>MostlyText’s Markdown preview is native SwiftUI, built with Textual, with native Markdown rendering and selection. The Markdown engine—swift-markdown, with cmark-gfm underneath—parses off the main thread with a short debounce and records which source lines each block came from. That map drives scroll sync today, and is the foundation for roadmap work such as editing in the preview.</p>

        <h3>Local diagrams, and maths still under verification</h3>
        <p>Mermaid, D2 and Graphviz fences render locally, in preview and in export. Equation rendering is also local, but it is still under verification: development builds have known inline-math issues. Nothing is sent anywhere. WaveDrom was evaluated and deferred because its documented rendering path relies on <code>eval()</code>; I didn’t want arbitrary code execution as the price of timing diagrams.</p>

        <h3>Documents behave like Mac documents</h3>
        <p>I planned an in-app tab bar and a single workspace window. Building it showed that was the wrong call, and the app now uses native window tabs: one window per document, grouped by macOS, with a sidebar per window. The development work includes atomic saves, recovery and external-file conflict handling. These are behaviours to test, not a blanket guarantee that the alpha cannot lose work. Please use copies of documents while testing.</p>

        <h2>Why the name is changing</h2>
        <p>MacDown 2 becomes MostlyText. The new identity is done, and this website uses it, but the app keeps the old name until the end of the 1.0 work. An app’s name and identifiers decide where macOS keeps its settings, recovery copies and sessions, and which app opens your Markdown files. Renaming carelessly could make an upgrade look like it lost everything, so the plan is to rename once and test migration on fresh installs and upgrades.</p>

        <h2>What’s not done</h2>
        <p>Plenty. The <a href="/roadmap/">roadmap</a> lists every work area. The big ones before 1.0 are everyday editor essentials—multiple cursors, find and replace across a folder, Quick Open—themes and Quick Look, localisation, and release work: signing, notarisation and a verified build. There’s no date for 1.0; it ships when those checks pass.</p>
        <p>After 1.0, the plan includes keeping source and preview locked together, real table editing, and editing directly in the preview, each with a page on why it’s harder than it looks.</p>

        <h2>Try it</h2>
        <p>The alpha is a source build: macOS 26, Xcode 26 and XcodeGen. Its Release build commands were verified on Apple Silicon; the release notes do not claim a fresh full test-suite pass. There is no prebuilt app download. The <a href={ALPHA_URL}>release notes</a> have the exact commands. Please use copies of documents.</p>
        <p>What I’d love to hear:</p>
        <ul>
          <li>anything that renders differently from what you expect;</li>
          <li>documents that make it slow—a sample helps more than a description; and</li>
          <li>what would stop you switching from your current editor.</li>
        </ul>
        <p>Issues go to <a href={ISSUES_URL}>the MostlyText issues page</a>. If you can’t build it yet, watch the repository for releases (<strong>Watch → Custom → Releases</strong>) to hear when signed builds arrive.</p>
        <p>Thanks to Tzu-ping Chung and everyone who built MacDown. Its licence, copyright and history come along for the ride.</p>
      </div>

      <aside className="blog-callout" aria-label="Build the alpha">
        <h2>The alpha is ready to build.</h2>
        <p>It is source code with build instructions, not a signed download. Use copies of documents while testing.</p>
        <div className="release-actions"><GitHubLink className="button" href={ALPHA_URL}>Build the alpha from source</GitHubLink><a className="text-link" href={RELEASES_URL}>Release notes</a></div>
      </aside>
    </article>
  </main>
}
