// The written-out part of each roadmap detail page: what the hover card leaves out.
// Chapters draw on the epic documents' context, acceptance criteria and out-of-scope
// notes in the development repository; versions on the product direction in
// roadmap-data.json. Nothing here adds scope, dates or commitments the sources don't make.
export type Narrative = {
  intro: string[]
  practice?: string
  checks?: string[]
  checksNote?: string
  guardrails?: string[]
  notIn?: string[]
  pullRequests?: number[]
}

export const statusMeanings: Record<string, string> = {
  implemented: "in the development code, still subject to the release checks.",
  development: "work or hardening is underway, with an open issue or pull request.",
  remaining: "work or verification still needed before 1.0.",
  planned: "an accepted direction; the detailed scope isn’t committed.",
  provisional: "to be re-checked once earlier versions prove the approach.",
  horizon: "an ambitious idea, not ready to build.",
  "demand-gated": "goes ahead only with clear demand and the capacity to support it.",
  deferred: "outside 1.0, with no schedule.",
  undecided: "needs evaluating, or a decision, before anyone commits to it.",
}

export const narratives: Record<string, Narrative> = {
  "write-find-and-organise": {
    intro: [
      "This is the editor you sit in all day: opening and saving files, native Mac windows and tabs, a fast text view, the outline of headings, the folder sidebar, the Markdown shortcuts that carry on a list when you press Return, and settings that apply straight away.",
      "MostlyText rebuilt these rather than patching the old MacDown, which re-rendered a web page on every keystroke and depended on unmaintained parsers. The risky parts, saving, recovering after a crash and noticing when another app changes your file, were treated as data-safety work with their own tests.",
      "Almost all of it is merged. The last piece, everyday editor essentials, has its features in the development code: line numbers and a status bar, multiple cursors, find and replace across a folder, Quick Open, line tools, snippets and line-ending control. It stays “being built” until its release checks and remaining safety proof are closed.",
    ],
    checks: [
      "Force-quit after editing a document you haven’t saved, and the text is there when the app reopens.",
      "A failed save, for example to a folder you can’t write to, never loses your text or its recovery copy.",
      "When another app changes a file you have open, a clean document reloads; one with unsaved edits keeps them and shows the conflict.",
      "A 1 MB Markdown file shows text in under 300 ms, typing stays under 50 ms a keystroke, and a 10 MB file opens without the spinning cursor.",
      "Opening the same file twice never makes a second tab, and closing a tab with unsaved changes always asks first.",
      "Quit with five documents open, and all five come back where you left them.",
      "Every setting applies to documents that are already open, without relaunching.",
    ],
    checksNote: "Issue 203 records one case where the keystroke budget isn’t met yet: re-parsing a 1 MB document.",
    notIn: [
      "Language-server IDE features, a terminal, a Git interface, a debugger or an AI sidebar.",
      "A minimap, code folding, a hex editor, SSH or a global keyboard-shortcut editor.",
      "The full TextMate or VS Code snippet grammar.",
    ],
    pullRequests: [472, 462],
  },
  "explain-the-technical-work": {
    intro: [
      "The part of MostlyText that turns text into something you can read and send: a native Markdown preview, equations, diagrams in Mermaid, D2 and Graphviz, and export to standalone HTML and PDF.",
      "The preview is drawn natively rather than as a web page, so it keeps up with typing and scrolls alongside the source. Diagrams and equations render locally on your Mac, without sending the document anywhere. Preview and export share one renderer, so what you export is what you checked.",
      "The features are merged. What remains is correctness and safety: headings and the table of contents that link reliably, dollar signs and currency that aren’t mistaken for maths, and strict limits on which local files the HTML preview and export may read, so a document can’t reach files it shouldn’t.",
    ],
    checks: [
      "Typing updates the preview within 150 ms, and scrolling the source keeps the preview within a screen of the matching block.",
      "If a diagram or equation fails, you see its source and a useful message; the rest of the document still renders, and the app doesn’t crash.",
      "A failed diagram never silently drops your text from an export.",
      "Exported HTML of the test documents matches the approved output, and any difference is reviewed rather than assumed.",
      "PDF export paginates correctly and keeps code blocks together where it reasonably can.",
      "Text filters, the scripts you can run on a selection, keep your original text if they fail, time out or return something unusable.",
    ],
    notIn: [
      "More diagram languages, or new Markdown syntax. WaveDrom was assessed and turned down for 1.0.",
      "ePub and hosted rendering.",
    ],
  },
  "feel-at-home-on-a-mac": {
    intro: [
      "The work that makes MostlyText belong on a Mac rather than merely run on one: themes that agree across the editor, preview, diagrams and export; Quick Look previews of Markdown files in Finder; Open With and document icons; accessibility; and the app in languages other than English.",
      "The visual polish, the welcome document and the accessibility code work are merged. Ahead: at least eight bundled themes, four light and four dark, checked for contrast; Quick Look; hardening so files and settings behave under pressure; and final localisation, which comes late on purpose, after the interface stops changing.",
      "French, Polish and Japanese starter translations exist. They’re a baseline, not finished language quality: native speakers still need to review them.",
    ],
    checks: [
      "The app looks right in light and dark mode, with transparency and increased contrast on or off.",
      "Every bundled theme passes contrast checks, and diagrams either follow the theme or fall back to a safe neutral style.",
      "Quick Look shows a safe, static preview of a Markdown file, with equations and diagrams, and falls back safely when a file is too large to render.",
      "Settings from the old MacDown come across key by key, without overwriting anything already set in the new app.",
      "VoiceOver and the main journeys are checked on a real Mac, in English and in other languages.",
    ],
    notIn: [
      "Quick Look for every kind of source file, Spotlight, Share or Finder Sync extensions.",
      "A theme marketplace or a remote theme gallery.",
    ],
    pullRequests: [476, 477, 473, 474, 475],
  },
  "the-move-to-mostlytext": {
    intro: [
      "MostlyText began as MacDown 2, a rewrite of the open-source MacDown editor. This chapter is the visible crossover: the app’s name, icon and identifiers change, your settings and documents carry over, the command-line tool becomes mostlytext, and the code moves to its own repository.",
      "The identity is decided and the icon is on real builds, but the app is still called MacDown2.app. Renaming it safely is the work: fresh installs and upgrades from MacDown 2 must both keep preferences, sessions, recovery files, recent folders, snippets and custom themes. The MacDown lineage, its MIT licence and its copyright stay intact.",
      "It also covers how official builds will reach people. The direction is open-source MIT code with affordable paid official builds, sold directly without DRM and through the Mac App Store, as a one-time purchase with no subscription, account or activation. Timing and channels are still being reconciled; today’s testing alpha is source-only, with nothing to buy.",
    ],
    checks: [
      "A Mac upgrading from MacDown 2 keeps every setting, session, snippet and theme, and a fresh install starts clean.",
      "The icon reads correctly in Finder, in the Dock and at small sizes.",
      "The repository is mirrored with its full history at the final cutover, and the release commit is identical in both places.",
      "The website offers the real download, requirements, documentation, privacy, licence and support, with screenshots from the release build.",
    ],
    notIn: ["Windows and Linux versions."],
  },
  "a-verified-release": {
    intro: [
      "1.0 isn’t a date; it’s a set of checks. This chapter is how a build becomes a release you can trust: a stabilisation gate, a private signed candidate tested on a real Mac, final localisation and an interface freeze, a final signed candidate with its source and licence evidence, the same checks repeated on those exact files, and only then the public release.",
      "Each step guards the next. If anything that goes into the app changes after the final candidate, verification starts again. The matching source archives are published before the final build, so its licence notices can point at them.",
      "The project foundations are done. The source-only v0.1.0-alpha.1 testing prerelease exists, but it doesn’t count towards these steps, and no date is promised for 1.0.",
    ],
    checks: [
      "A fresh review finds no serious open problem (nothing rated P0 to P2) that affects the release.",
      "Clean installation, migration from MacDown 2 and a signed update are rehearsed on a private candidate first.",
      "The final candidate is signed with a Developer ID, notarised and stapled, and its disk image passes its checks.",
      "Every licence item is closed, including notices, Graphviz and D2, parser provenance, locked dependencies, themes, a software bill of materials and the source offer.",
      "The files published are exactly the files that were verified, and the update feed goes live last.",
    ],
  },
  "1-0-x": {
    intro: [
      "The first releases after 1.0 do one thing: make it boringly reliable. Crash, save, recovery and security fixes come first, then installation, updates, signing and compatibility.",
      "Corrections that come in through support go ahead of any new architecture. New capabilities start with 1.1.",
    ],
    practice: "If 1.0 has a problem saving to a particular kind of drive, or updates misbehave on one Mac, a 1.0.x release fixes that before anything from 1.1 ships.",
    guardrails: ["No new architecture until the launch is stable."],
  },
  "1-1": {
    intro: [
      "With source and preview side by side, it’s easy to lose track of which paragraph you’re looking at. 1.1 keeps the two together.",
      "A Line Lock you can switch on, anchored to stable points in the source, lets the preview follow the line you’re editing or the whole document, in one direction or both. Matching blocks are highlighted on each side, and clicking in either view takes you to the same place in the other.",
    ],
    practice: "You’re editing a long README. Click a heading in the preview and the caret lands on it in the source; move the caret, and the matching block lights up in the preview.",
    guardrails: ["Free linked scrolling comes only after the mapping between source and preview is proven accurate."],
  },
  "1-2": {
    intro: [
      "Markdown tables are rows of pipes and dashes, and editing them by hand is tedious. 1.2 makes the editor understand them.",
      "Move between cells from the keyboard; add, remove and reorder rows and columns; and copy a rectangle of cells to or from a spreadsheet.",
    ],
    practice: "Copy a block of cells from a spreadsheet, paste it into a note, and get a Markdown table you can carry on editing cell by cell.",
    guardrails: [
      "Tidying a table’s formatting is something you ask for; nothing reformats it on its own.",
      "One undo reverses one table change.",
      "Nothing else in the file is normalised along the way.",
    ],
  },
  "1-3": {
    intro: [
      "Getting content into a Markdown file is often the messy part. 1.3 turns what’s on the clipboard, or dragged in, into clean local documents.",
      "Start a new document from the clipboard, with Markdown detected. Pasted and dropped images become local files whose names never clash. HTML and rich text convert to Markdown that you review before it lands, and it works the other way too: copy as rich text or HTML.",
    ],
    practice: "Drag a screenshot into a note: it’s saved as a local file next to your work, and a link to it goes in where you dropped it.",
    guardrails: [
      "Conversions are shown for review before they change anything.",
      "Plain text can always be pasted as plain text.",
    ],
  },
  "1-4": {
    intro: [
      "Sometimes you’d rather fix a typo in the rendered page than hunt for it in the source. 1.4 lets you edit the common cases from either side.",
      "Edit paragraphs and headings in the rendered view, with basic formatting, links and task checkboxes where the mapping to the source is safe. Both views share one undo history and one unsaved-changes state.",
    ],
    practice: "Tick a task in the rendered checklist: the source changes from “- [ ]” to “- [x]”, and nothing else in the file moves.",
    guardrails: [
      "Each edit changes only the characters it needs to.",
      "Where an edit would be ambiguous, it’s made in the source instead of guessed at.",
    ],
  },
  "1-5": {
    intro: [
      "If 1.4 proves that rendered editing keeps the source faithful, 1.5 widens it: lists and quotes first, then code and tables where that’s safe, with better mapping of selections and the caret between the two views.",
    ],
    practice: "Reorder items in a rendered list, and only those lines change in the source.",
    guardrails: [
      "The source is never hidden or normalised.",
      "It expands only after 1.4 proves the edits are faithful.",
    ],
  },
  "1-6": {
    intro: [
      "Text underneath, with the view that fits the job. A CSV or TSV file can be shown as a table as well as raw text.",
      "Work on cells, rows and columns, paste rectangles, and sort or filter the view without touching the file. Large files stay quick because only the rows on screen are drawn.",
    ],
    practice: "Open a large CSV export and filter the view to one customer. The file on disk is unchanged until you edit a cell.",
    guardrails: [
      "Sorting and filtering change the view, never the file.",
      "Only what real formats prove they share becomes a general system.",
    ],
  },
  "1-7": {
    intro: [
      "Review and recover without turning into a source-control client. 1.7 keeps a local history at each save.",
      "Compare the current text with earlier saves or snapshots, restore or copy from them, and see changed lines marked in the margin. The same comparison helps when a file changes on disk while you’re editing it.",
    ],
    practice: "You rewrote a section an hour ago and want one paragraph back: open the history, compare with the last save and copy just that paragraph.",
    guardrails: [
      "History stays on your Mac, and the space it takes is bounded.",
      "It isn’t a Git client.",
    ],
  },
  "1-8": {
    intro: [
      "One workspace, ordinary files. Name a workspace that holds several folders at once, with Quick Open and search across all of them.",
      "Recent workspaces remember their state and cope when a folder has moved or a drive isn’t connected.",
    ],
    practice: "Keep a project’s documentation and your own notes in one workspace and search both, without moving a file.",
    guardrails: ["No vault, database or proprietary storage: your folders stay ordinary folders."],
  },
  "1-9": {
    intro: [
      "Smarter links, still just files: completion and navigation for relative links and headings, and a check for broken links.",
      "Wikilinks come only if people ask for them, and backlinks are limited to files that are already indexed. This version waits on clear demand.",
    ],
    practice: "Start a link to another file, pick a heading from the list, and later see which links no longer point anywhere.",
    guardrails: ["No graph view, vault or task model."],
  },
  "1-10": {
    intro: [
      "Write in text, publish like a real document. A publication profile describes a true print layout: typography, page size and margins, headers and footers, and generated numbering.",
      "The same profile drives the preview, HTML and PDF, and can be edited visually or as text. Portable style packages and a gallery would come only once the local model is mature. This is a longer-term idea, not ready to build.",
    ],
    practice: "Write a report in Markdown, choose a profile with your page size and running header, and the PDF matches the preview.",
    guardrails: ["Word (DOCX) output would follow only once publication styles map to it exactly."],
  },
  later: {
    intro: [
      "Ideas without a version number. Some wait on demand, some need evaluating before anyone commits to them, and one is a legitimate feature that simply isn’t scheduled.",
      "Mac editing stays the priority: an iPhone and iPad version is an exploration for after macOS 1.0, and only if there’s demand.",
    ],
    notIn: [
      "Language-server IDE features, a terminal, a Git interface, a debugger or an AI sidebar.",
      "A general plugin or theme marketplace, or a remote theme gallery.",
      "A minimap, code folding, a hex editor, log tailing, SSH or SFTP, a global keyboard-shortcut editor or a Unicode inspector.",
      "The full TextMate or VS Code snippet grammar.",
      "Quick Look for every kind of source file, Spotlight, Share, Services or Finder Sync extensions.",
      "More diagram languages, or new Markdown syntax.",
      "ePub and hosted rendering. Word (DOCX) is only a later, conditional publishing candidate.",
      "Windows and Linux.",
    ],
  },
}
