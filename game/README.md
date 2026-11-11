# Valley & Crown game source

Current tested Web beta: `vc-79ebcaef19e3`. [Play](https://penny323mo.github.io/valley-crown/builds/vc-79ebcaef19e3/).

Tested source `ce2ea3d2513bd79cf62cf5c651abe3c47aad8513`, game tree `cadc77674b0b3184e7c3af9961f3e6ffdac507e9`. Later release documentation does not alter runtime bytes.

- Fixed the first battlefield tap after swiping the action strip. Ordinary producer swipe followed by first worker selection, direct ground/resource commands, and immediately available building actions are covered.
- Four resources, age research, eight worker-buildable structures plus the starting town center, advanced stable/workshop gates, cavalry/siege gameplay and producer controls. Military models and weapon grips remain provisional, not final art.
- Existing illustrated Traditional Chinese menu, compact Stop and terrain retained. The menu illustration is artwork, not a gameplay screenshot.

642 controlled engine assertions and two byte-identical Web exports passed in [run43022406764](https://github.com/penny323mo/valley-crown/actions/runs/43022406764). Three separately bounded390x844 real-Chrome touch scenarios passed in [run43024327364](https://github.com/penny323mo/valley-crown/actions/runs/43024327364); actual resource/age, queue and building-palette screenshots were inspected. These are emulated touches, not physical-phone acceptance.

Prior build542 had a headless normal match through keep-destruction victory in [run43017137336](https://github.com/penny323mo/valley-crown/actions/runs/43017137336), and four menu viewport profiles in [run43017262730](https://github.com/penny323mo/valley-crown/actions/runs/43017262730). Those are labelled historical evidence rather than automatically transferred new-build acceptance.

Not full-game acceptance. Final cavalry/siege/grip art, rendered full-match progression, normal-camera combat/projectile/HP readability, physical devices and audio remain outstanding. Earlier failed receipts remain failed.

Prior10d6,21ae,cf764 anddd795 routes preserve exact original bytes and metadata. Deployments still depend on Actions artifacts expiring2026-12-11; durable retention is not resolved by this update. See WEB_EXPORT_MANIFEST.json for exact hashes and scope.

Open project.godot in Godot4.6.3. Ordinary entry is the main menu. Preserve existing UID/import descriptors, art/.gdignore, Web exclusions and bundled licenses. Build identity is deterministic pre-import source; generated sidecars are inventoried separately.
