# First stdin qualification preparation failure

Exact sourceb25916df, actual PR checkouted1f7201 on main427d15fa.
First workflow42382179655 fails at host/ancestry admission. Original checkout
uses --depth=1; required actual main427 is not a valid local commit object, so
strict merge-base exits128. Zero product/control builds or native/UI tests run;
all three later build/execute steps are skipped. No generated artifact is
published. Original first full logs and Compliance42382179625PASS are retained.

Correct checkout to fetch-depth0, keeping the required real ancestor and every
host/native/assertion boundary. Prove the same missing-anchor refusal with an
owned local shallow Git fixture and its success after full history is fetched.
This is a workflow preparation defect, not a product/native result or permission
blocker. Do not merge to bootstrap workflow discovery, bypass ancestry, rerun the
unchanged failed source, or report Save-panel/stdin acceptance from this result.
Original full archives remain in the engineering build root and GitHub runs;
compressed source records and archive digests do not replace their raw evidence.
