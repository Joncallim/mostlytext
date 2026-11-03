# points-on-curve flatness origin: review evidence

The Rough.js publisher-lock evidence already links points-on-curve 0.2.0 as a
source-build input. Its complete package MIT text ships. This checkpoint traces
one named borrowed helper; it does not prove its exact retained minified runtime
or supply an independent rights determination.

## Verified chain

1. The official package archive's `src/index.ts`, lines 31–52, explicitly adapts
   `flatness` from Sean Thayne's 2010 [Offset Bézier Curves article](https://seant23.wordpress.com/2010/11/12/offset-bezier-curves/).
2. That article's flatness section cites Kaspar Fischer's 16 October 2000
   [Piecewise Linear Approximation of Bézier Curves](https://seant23.wordpress.com/wp-content/uploads/2010/11/piecewise_linear_approzimation.pdf).
   Page 3 attributes the approach and implementation to Roger Willcocks and
   describes permission given to Fischer; page 4 includes pseudocode and cites
   their September 2000 correspondence.
3. Thayne's [2013 reply](https://seant23.wordpress.com/2010/11/12/offset-bezier-curves/#comment-33)
   describes the larger codebase as closed source. His
   [2017 reply](https://seant23.wordpress.com/2010/11/12/offset-bezier-curves/#comment-127)
   describes contract work that he could not sell. These replies concern broader
   source requests; they do not independently decide the terms for this helper.

## Remaining question

Review the applicable grant and attribution for this specific adaptation through
all three sources. Distinguish the mathematical method from the particular code,
and permission to a document's author from any permission for later reuse. No
MIT/BSD/public-domain grant is inferred for the article or paper. This is a
concrete upstream/independent-review input for MostlyText #14, not clearance or
a finding that any particular party infringed rights. No author was contacted.

[The manifest](manifest.json) records the official archive/member digests, exact
source range, article/comment anchors and observed primary-document hashes.
Full article/PDF copies and borrowed code are not redistributed here. Dynamic
article HTML may change; its digest identifies the observed audit input rather
than promising a stable upstream response.

The package licence, inventory, notices, renderer selection and six strict
release predicates remain unchanged. See the [source-build checkpoint](../nested-build-attribution/README.md)
and [remaining review packet](../../UPSTREAM_REVIEW_QUESTIONS.md).
