# Valley & Crown / 霧谷王旗

Current tested Web beta: `vc-10d6c6145978`. [Play](https://penny323mo.github.io/valley-crown/builds/vc-10d6c6145978/) or visit the [website](https://penny323mo.github.io/valley-crown/).

Tested source `3e84f07b5984135572c089a70fd90392810b8017`, game tree `5047b4ffcd5b7fea49a668d7769f7fa80a909062`. This documentation update does not alter tested runtime bytes.

## This menu update
- Original illustrated castle-valley backdrop, Traditional Chinese serif title and restrained dark/gold composition. The menu illustration is not a gameplay screenshot.
- Responsive portrait/landscape layouts with large persistent actions; compact short landscape prioritizes artwork and controls rather than repeated title/crest.
- Single-finger Help scrolling reaches the final paragraph while Back stays visible. Rotation, interrupted touches, pause/resume, New Match cancellation and confirmed restart were exercised.

## Verified scope
- 487 headless controlled assertions across eight suites, including243 menu checks, and two byte-identical Web exports: [export run43008259514](https://github.com/penny323mo/valley-crown/actions/runs/43008259514).
- Real Chrome tests at320×568,390×844,844×390 and1440×900, plus rotated views: [browser run43011239931](https://github.com/penny323mo/valley-crown/actions/runs/43011239931). Actual menu/Help/pause/confirmation screenshots were inspected. Network, input identity, resource and cleanup gates passed.
- Startup and confirmed restart select the owned town center, as the product intends; retained worker selection, tick progression, economy/counters and camera are checked separately.

Not full-game acceptance. Physical phones, audio, OS interruptions, complete rendered combat and played victory remain unverified. Weapon/tool/shield corrections and expanded military progression are not included. Earlier failed receipts remain failed.

The prior [menu/touch beta](https://penny323mo.github.io/valley-crown/builds/vc-21ae974acec8/), [construction beta](https://penny323mo.github.io/valley-crown/builds/vc-cf764648c52f/) and [earlier beta](https://penny323mo.github.io/valley-crown/builds/vc-dd795d96905c/) retain their exact bytes/manifests. Deployment still depends on retained Actions artifacts, whose current release expiry is2026-12-11; this release does not resolve durable storage. See `WEB_EXPORT_MANIFEST.json` for exact hashes and scope. Public served-byte verification is separate after deployment.
