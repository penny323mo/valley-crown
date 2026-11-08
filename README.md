# Disabled hosted narrow material render delivery

This directory is a standalone proposed public job tree, not a run authorization.
Checkout/upload actions are immutable-commit pinned; one fixed concurrency
group uses cancel-in-progress=false. PYTHONDONTWRITEBYTECODE=1 is set by the
workflow before any Python process; child commands use /usr/bin/python3.
The push trigger is restricted to ci/material-render-proof-v1 and explicit input paths.
The workflow job is unconditionally disabled, DELIVERY.json.execution_enabled
is false, actual accepted generation, baseline and native output identities are populated; three capture input reviews are accepted, but the future import certificate
remains null. Prepared locks are source-reviewed and await the verified actual
certificate; final delivery/workflow execution gates remain disabled. No network, engine, publish, workflow,
render or upload was performed while preparing it. The earlier reviewed source
files, READY_GATE and SOURCE_REVIEW_SNAPSHOT were not modified.

## Fixed delivery chain

1. Common delivery helper checks the closed public-file manifest, exact reviewed
   contract/core/workflow/helper, and hosted execution boundary.
2. It retrieves four separately pinned artifact outer ZIPs: old_licensed,
   old_native, generated, native_accepted. API run/artifact/source-commit/success
   and outer SHA are verified before closed-member extraction. Authentication
   is not sent on storage redirects. No actions/download-artifact is used.
3. Reconstruct the accepted baseline using the35 byte-identical public blobs
   from commit99c15f8c03f57e6f26f032b25b23d6d6056c1266 and the native worker's
  12-command file-only reconstruction helper. Verify exact baseline192.
4. The unchanged assemble_material_source.py uses independently accepted
   generated output, exact reviewed generator, geometry comparator and generation
   review to recreate the same pristine assembled192 used by native conversion.
5. The unchanged prepare_render_source.py binds the accepted native39 artifact,
   actual independent output review, native11 delta and final197 lock, then
   builds final197 source ZIP and guarded-import manifest. All three prepared
   render locks must already match those exact deterministic ZIP/manifest bytes.
6. Before any import, verify each actual independent review binds the prepared
   lock core, binder and assembly-helper hash. Retrieve the official engine via
   the common helper's bounded single-member ZIP extraction and fixed binary
   SHA. Install only the same official Ubuntu display packages as accepted runs.
7. Run unchanged clean-import resource guard. Then reviewed file-only binder
   validates actual certificate/cache/receipts and fills only the certificate
   SHA in each lock. No fabricated future certificate hash is used.
8. Exactly three serial invocations, with no matrix or arbitrary scenario list:
   studies844×3908 frames, portrait390×8442, landscape844×3902. Every run is
   followed immediately by its strict paired scanner; failure stops the chain.
9. stage_render.py verifies the exact20+8+8 scanned files, three scan reports,
   filenames and unchanged bytes. It additionally binds exactly seven provenance
   files to every guard receipt: provenance/import-complete.json, import.json,
   import.invocation.json, import.log, studies-lock.json, portrait-lock.json and
   landscape-lock.json. Import cleanup/command/helper/source identity and
   certificate/receipt/invocation/log hashes are checked, plus closed paths,
   finite JSON, privacy and size limits. Only safe-render/'s46 files are eligible for
   success-only upload. No source assets, imported cache, private environment, or unrelated files are
   retained. The exact import log is provenance, not blanket debug retention.
10. If the capture chain fails, the separately reviewed collector may retain only
    bounded import/log/receipt/invocation and owned Godot/Xvfb cleanup diagnostics.
    It never reads/copies frame payloads, source assets or caches. Cleanup,
    lifetime, readiness, hash, privacy and size checks must pass first. Only its
    diagnostics_scanned marker allows a separate UNACCEPTED_DIAGNOSTIC upload;
    this cannot confer capture, runtime or material acceptance.

The raw evidence remains **human material pixel review required**, including
ordinary visible worker skin/clothing and possible silhouette whitening. A
successful provenance scan is not visual/material acceptance. Fixed20fps means
simulation control, not measured phone performance.

## Required final binding (not available in this draft)

DELIVERY.json uses the common helper schema. `bindings` maps semantic labels to
`{path,sha256}` records, never an unstructured relative-path map. Every public
code/control input is covered by DELIVERY_FILES.json. Reviews and all exact
future bindings must be regenerated after any source change; merely switching
execution_enabled or the workflow condition cannot pass admission.

Fill actual artifact run ID, artifact ID, head commit, outer ZIP SHA and closed
member hashes for all four artifacts. The common helper requires the accepted
old artifact identities unchanged. No assembled-source artifact is introduced.
Generated artifact outer bytes remain available at downloads/generated.zip for
the independently reviewed assembler. The generator source under tools/ is the actual independently accepted
0d66d1c6836192d18a15d1425e007c6ecf6b37519a3d87d3c6afd553d5e9318a revision.
Generation run42447623186/artifact13604855256 is pinned to its actual19 members
and e7897331adf344ebcda27da74ee2a9e92b204ec03a9b230f6903449339c1729b outer ZIP.
Generation and native source conversion are now independently accepted; rendered pixels remain pending.
Native run42448936212/artifact13605245411 is pinned to its39 exact members and
62d971c281dbd32584df71f36f1e8bab75120b2e4718d9d91016f7ff18e1c833 outer ZIP.
The accepted final build is vc-84a95dfec970. Its exact197-source render bridge
ZIP is233850979155595d169a97a5c5fe570f7dedc6057899af83916ecf050c603944;
manifest077e6b449e74ad97b9597692da9fe4e78a927a566fabdbc27b9aac4c61179e3e.
The existing source packaging helper produced and verified these locally without
executing an engine; the hosted coordinator must reproduce the exact bytes.

Already bound independent reviews cover controls/MATERIAL_SOURCE_INPUTS.json,
GENERATION_REVIEW.json, MATERIAL_RENDER_SOURCE_INPUTS.json,
NATIVE_OUTPUT_REVIEW.json, and the studies/portrait/landscape prepared locks and
reviews. The diagnostic collector has a separate independent source review. Final
workflow/delivery review remains pending. Future lock import_certificate_sha256 remains null until the actual
clean import; the binder then fills just that field. Native outer artifact
identity and inner runtime-delta SHA are distinct and must not be conflated.

The final delivery review must contain peer_reviewed=true, delivery_core_sha256
(canonical contract excluding review), helper_sha256, and workflow_sha256.
The common helper and fixed workflow bytes must be included in that review.
The coordinator validates common retrieval/public-tree admission once before
its fixed prepare/import/capture sequence creates work outputs. It rechecks
all bound code/control bytes at every internal phase. No later common fetch
or engine operation is allowed after work begins.
Prepared-lock reviews use the unchanged binder's exact schema. Any future
approved workflow-condition change also changes its required SHA/review.

## Invocation surface, only in separately authorized hosted workflow

    /usr/bin/python3 delivery_helpers.py preflight --contract DELIVERY.json --mode render
    /usr/bin/python3 delivery_helpers.py fetch --contract DELIVERY.json --key old_licensed
    /usr/bin/python3 delivery_helpers.py fetch --contract DELIVERY.json --key old_native
    /usr/bin/python3 delivery_helpers.py fetch --contract DELIVERY.json --key generated
    /usr/bin/python3 delivery_helpers.py fetch --contract DELIVERY.json --key native_accepted
    /usr/bin/python3 delivery_helpers.py engine --contract DELIVERY.json
    /usr/bin/python3 run_render_delivery.py --contract DELIVERY.json --phase all --engine engine/Godot_v4.6.3-stable_linux.x86_64

The workflow installs the accepted official Ubuntu display packages before
engine retrieval. Coordinator children receive only an allowlisted nonsecret environment.
Its token is read-only GITHUB_TOKEN, used only by
the common artifact retrieval helper. Guards launch the engine with their
unchanged private environment, pidfd/Xvfb/readiness/time/RSS/OOM/cleanup/cache
checks. No substantive renderer/helper code was rewritten in this delivery.

## Local verification

    /usr/bin/python3 -m unittest discover -s . -p 'test_*.py'

Tests use static comparisons and explicitly synthetic file fixtures only.
They do not claim fixtures are real frames or execute engine/network commands.
Check and remove test-generated __pycache__ before freezing the public tree.
DELIVERY_FILES.json covers the exact standalone tree except itself; a final
review must regenerate it if any binding or code changes.
