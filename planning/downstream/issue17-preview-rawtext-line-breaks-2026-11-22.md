# Preview source review: rawtext boundaries and CR-only links

## Owner summary

Two small Preview paths did not preserve the behavior of the documents they
read. A CR-only Markdown file lost cross-block reference links because the
definition scan split only on line feeds. Separately, an HTML policy-injection
scan could stop reading a `<script>` or `<style>` element at an unrelated closing
tag and insert its policy meta tag into authored text instead of the document
head. The preview response's Content-Security-Policy header remains the primary
enforcement boundary; this finding does not establish a network escape.

## Source and correction

Reviewed `main` at `97404536394d9383165ded08099dbb8c009d3395` for the
small Preview paths named in MostlyText #8/#17. The correction makes the
reference-definition scan recognize LF, CRLF and CR as physical line endings
without rewriting source. The HTML scanner retains the name of the active
text-bearing element, recognizes only its matching closing tag, and treats
`<plaintext>` as consuming the rest of the input. The response policy, WebKit
configuration, document bytes and renderer dependencies are unchanged.

## Evidence and limits

Added deterministic tests before the product correction. On the unchanged
production source, the focused run failed: CR-only and mixed-break definitions
were missing; four mismatched rawtext-close cases and the plaintext case placed
the meta tag after a fake `<head>`. The same focused run after the correction
passed 56 tests in five selected suites. The earlier failure is retained as
the failing-before result; it is not relabeled by the later pass.

This is source and package-test evidence. The final installed Release app's
HTML preview, local resources, hostile documents and cross-block link display
still require the protected native acceptance tracked by #13/#17/#8. No
issue-wide acceptance checkbox or signed-artifact conclusion follows from
these two repairs.
