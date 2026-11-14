# Selected Mermaid nested snippets — 14 November 2026

The [reproduction](reproduction.json) reads the exact published Mermaid 11.17.2 map and the locked npm members. The included audit script rejects changed archive hashes and requires source-map `sourcesContent` to equal the npm member bytes before counting positions. It measures 1,989 outer positions in layout-base 2.0.1's SVD body, 21 in each layout-base RandomSeed function (1.0.2 and 2.0.1), and 314 in the scoped Cytoscape rounded-corner body. These are mapped positions, not runtime call counts, copied-source grants, or whole-module ownership claims.

The SVD/hypot source [expressly credits JamaJS](https://github.com/dragonfly-ai/JamaJS) and lists its changes: array input/dimensions, return shape, hypot parameter types and declarations. The pinned package includes an Apache-2.0 text; the [complete JamaJS reference licence](https://github.com/dragonfly-ai/JamaJS/blob/6d24a590ea74b16d99c96d90b936f7edea34af78/LICENSE) is now distributed as a scoped notice. The reviewed reference archive has no separate NOTICE file. The matching reference does not identify the exact historical copy revision. No other layout-base code is relabelled as JamaJS.

JamaJS describes itself as a transpilation of JAMA. [NIST's JAMA project page](https://math.nist.gov/javanumerics/jama/) identifies the MathWorks and NIST reference implementation as public domain and gives its own copyright and no-warranty notice. This is a source attribution reference, not a substitute for JamaJS's Apache text or proof of the exact copied JamaJS revision. No omitted JamaJS NOTICE is inferred from the reviewed archive's absence of that file.

The two RandomSeed copies cite [Stack Overflow answer 19303725](https://stackoverflow.com/a/19303725), by Antti Kissaniemi. The answer's first publication was 10 October 2013; its displayed latest edit is 23 October 2018. Cytoscape's rounded-corner source cites [answer 44856925](https://stackoverflow.com/a/44856925), by Blindman67, first published 1 July 2017 and edited in 2023. [Stack Overflow's licensing help](https://stackoverflow.com/help/licensing) assigns CC BY-SA 3.0 to revisions before 2 May 2018 and CC BY-SA 4.0 to later revisions, and says the revision timeline supplies each revision's terms. Neither an answer's first date nor the current page proves which revision these bundled adaptations used. Their grant, attribution and any replacement choice remain open for independent rights review. The source packages' own MIT labels do not resolve this nested provenance; no whole-application ShareAlike conclusion is asserted.

The js-yaml 4.3.0 `lib/exception.js` header links to [question 8458984](https://stackoverflow.com/questions/8458984). The question and answers discuss customary Error subclass and stack-capture techniques. A narrow comparison found no uniquely matching YAMLException expression. It is classified as a related technique citation rather than a confirmed borrowed-code notice. Reassess if a matching revision is identified.

Reproduce from retained npm archives (symlink or copy the five pinned archives to the names expected by `audit.py`):

```sh
python3 compliance/evidence/mermaid-nested-snippets/audit.py \
  --inputs /path/to/mermaid-inputs \
  --output /tmp/mermaid-nested-reproduction.json
cmp compliance/evidence/mermaid-nested-snippets/reproduction.json \
  /tmp/mermaid-nested-reproduction.json
```

The 3,980 original parser references retain their earlier technical dispositions and independent-review requirement. No parser, Mermaid bundle, package revision or release predicate changes here.
