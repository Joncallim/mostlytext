# Framer-credited spring: historical comparison evidence

The current Cytoscape member credits Koen Bok/Framer under MIT. The missing
original adaptation revision remains a review question. This checkpoint narrows
its history without selecting a Framer version or substituting licence terms.

## What the source establishes

[Cytoscape's 26 August 2015 change](https://github.com/cytoscape/cytoscape.js/commit/b272f918d3bbd6a06e6935e9b184fe6f3b7a0965)
adds `generateSpringRK4` in `src/core-animation.js`; its immediate parent lacks
that symbol in the file. The added attribution already names Framer/Koen and MIT.

The complete historical function body matches an earlier
[Velocity source reference](https://github.com/julianshapiro/velocity/blob/d9cd60bc0c026adff6303869934bb58fc832e82f/velocity.js#L818-L900)
after removing block comments and whitespace. The reference is dated 20 August
2015, identifies itself as 1.2.2 in its file header, and carries the same
Framer/Koen attribution. Its [root licence](https://github.com/julianshapiro/velocity/blob/d9cd60bc0c026adff6303869934bb58fc832e82f/LICENSE.md)
is retained as a comparison input. The comparison is byte-structure evidence,
not a determination that Cytoscape actually copied from that exact revision or
that Velocity is a separate bundled package.

The already verified distributed Cytoscape 3.34.0 member still contains this
named helper and attribution, but its function text has formatting/transformation
differences. No byte-identical current-body or independent rebuild claim follows.

## What remains unresolved

Identify the actual Framer input and applicable grant/notice obligations for the
adaptation. The historical match supplies a specific contemporary reference;
it does not establish Framer's original revision, settle the retained BSD-style
comparison references, or independently clear the nested source. No arbitrary
MIT/BSD text, new dependency record or release clearance is introduced.

[The manifest](manifest.json) records immutable revisions, paths, source/text
hashes, function ranges and the exact comparison rule. The original files are
available through their primary links; their code is not recopied here. Complete
runtime/source-offer review and MostlyText #14 remain open. See the
[existing mapped Cytoscape evidence](../cytoscape-borrowed-attribution/README.md)
and [review packet](../../UPSTREAM_REVIEW_QUESTIONS.md).
