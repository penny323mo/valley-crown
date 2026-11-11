# Valley & Crown game source

Current integrated development build: `vc-79ebcaef19e3`. Repairs the first battlefield tap after an action-strip swipe, with an added viewport-routed regression. It retains military progression, faction-publication optimization and the illustrated menu. Tests for this new input repair are pending; cavalry/siege presentation remains provisional, not final art.

The preceding military source `422acc862d9fc56f1fe2c95440f411893ded5edf` / `vc-542ddb524e45` passed 626 controlled engine assertions, two identical Web exports, four real-browser menu profiles and a separately bounded headless normal match through keep-destruction victory. Its direct swipe-to-world browser test failed and motivated this repair; those earlier successes do not automatically validate the new bytes.

The latest released and separately verified menu beta remains [vc-10d6c6145978](https://penny323mo.github.io/valley-crown/builds/vc-10d6c6145978/). The historical release evidence below applies to that release, not automatically to these development bytes.

Integrated Godot4.6.3 source, deterministic pre-import build `vc-10d6c6145978`. Open `project.godot` in Godot. The ordinary entry is the main menu; Start creates the match.

Tested source `3e84f07b5984135572c089a70fd90392810b8017`, game tree `5047b4ffcd5b7fea49a668d7769f7fa80a909062`. This later README update does not change runtime bytes. The illustrated menu, single-touch Help scrolling and responsive actions are included alongside existing contextual touch, construction feedback and terrain.

487 controlled headless assertions and two identical Web exports passed in [run43008259514](https://github.com/penny323mo/valley-crown/actions/runs/43008259514). Real Chrome320×568,390×844,844×390 and1440×900 menu flows plus rotated views passed in [run43011239931](https://github.com/penny323mo/valley-crown/actions/runs/43011239931), with genuine screenshot review and strict network/cleanup checks. These are not physical-phone, full combat or victory acceptance. Fixtures include synthetic handlers and controlled states.

`python3 -B tools/stamp_build.py --dry-run` computes pre-import runtime identity. Import-generated UID sidecars are inventoried separately; do not restamp merely because import generated them. Keep existing UID files and import settings.

F12 gameplay screenshots write to `user://screenshots/`. Keep `art/.gdignore` and Web export exclusions. Existing native `.scn` assets must not be regenerated merely to run the project. Font, Godot, Quaternius and KayKit notices remain included; the original menu illustration and licensed title-font subset are documented in `THIRD_PARTY_NOTICES.txt`.

The historical released menu beta above does not include weapon/tool/shield grip corrections or expanded military progression. Public served-byte verification is separate from browser behavior.
