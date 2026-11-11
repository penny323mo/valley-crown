# Valley & Crown / 霧谷王旗

Current tested Web beta: `vc-cf764648c52f`. [Play](https://penny323mo.github.io/valley-crown/builds/vc-cf764648c52f/) or visit the [game website](https://penny323mo.github.io/valley-crown/). The [previous beta](https://penny323mo.github.io/valley-crown/builds/vc-dd795d96905c/) remains available.

Source is in [`game/`](game/). This release uses source commit `677096aaaa5131089971c2ec85b598ad20bd91da`, game tree `dec0eabb654f36c837e68db547d4282bea0754fb`. Later release documentation does not change those runtime bytes.

Unfinished buildings now distinguish active construction, travel, path search, stopped routes, waiting, missing builders, pause and pending commands. A stopped or reassigned builder no longer leaves a false arrival promise. Recovery directions explain how to assign a villager again. Labels use the unchanged shipped font. Construction, pathfinding and resource rules are unchanged.

Validation:
- 34 value-contract and 30 controlled synthetic HUD assertions, plus two byte-identical repeat Web exports: [run 42973027221](https://github.com/penny323mo/valley-crown/actions/runs/42973027221).
- Natural 390×844 Chrome touch flow: placement, Stop, stable unfinished progress, reassignment and resumed work, with readable screenshots and clean network/cleanup gates: [run 42977355259](https://github.com/penny323mo/valley-crown/actions/runs/42977355259). This is emulated touch, not a physical phone.

Historical `vc-dd795d96905c` passed 18 headless combat assertions in [run 42968247632](https://github.com/penny323mo/valley-crown/actions/runs/42968247632), not current-build visual combat acceptance. Earlier economy runs had deposit/training evidence but failed overall network gates and remain failed.

This is an incremental beta, not full-game acceptance. Physical iPhone/Android, audible audio, full combat play and long-match acceptance remain unverified. Exact files and scoped evidence are in the release manifest. Public served bytes are checked separately after deployment.
