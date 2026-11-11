# Valley & Crown / 霧谷王旗

Current tested Web beta: `vc-21ae974acec8`. [Play](https://penny323mo.github.io/valley-crown/builds/vc-21ae974acec8/) or visit the [website](https://penny323mo.github.io/valley-crown/).

Tested source commit `861ca5fa35e01b6a7fa96da1b2457ceea1b3c57c`, game tree `bc86e0554eee81d3aad007551367ac3372361d47`. This release documentation update does not change the tested runtime bytes.

## Changes
- Traditional Chinese opening menu, Help and match start. Returning to the menu pauses and retains the match; Resume continues it. Help navigation stays visible outside the scrolling text.
- Contextual touch: select a unit then tap ground or a target. Villagers expose build actions immediately. The compact Stop control no longer requires scrolling the action strip.
- Stone settlement courtyard, connected dirt paths and varied grass/earth terrain.

## Verified scope
- 260 headless controlled assertions across eight suites and two byte-identical Web exports: [run 42991393471](https://github.com/penny323mo/valley-crown/actions/runs/42991393471).
- Real Chrome emulated touch at 320×640 and 390×844: Help/Back, Start, cancel/resume, visible controls, direct ground movement and resource gathering, natural construction Stop/resume. Actual screenshots, strict network and cleanup checks passed: [run 42991819423](https://github.com/penny323mo/valley-crown/actions/runs/42991819423).
- Final screenshot review confirms readable 320px navigation and controls, readable construction guidance, and the terrain change. This is not a matched historical before/after comparison.

Not full-game acceptance. Physical phones, landscape browser pixels, audible audio, OS interruptions, complete rendered combat and a played victory remain unverified. A bounded earlier-candidate full-match attempt progressed through economy, construction, military production and AI combat but did not reach victory. Weapon/tool/shield grip corrections are not included. Failed earlier receipts remain failed.

[Construction beta](https://penny323mo.github.io/valley-crown/builds/vc-cf764648c52f/) and [earlier beta](https://penny323mo.github.io/valley-crown/builds/vc-dd795d96905c/) retain their exact bytes and manifests. Deployment currently depends on retained Actions artifacts; future redeployment must account for their expiry. See `WEB_EXPORT_MANIFEST.json` for exact file hashes, evidence and limits. Served-byte verification is separate after deployment.
