# Valley & Crown game source

This is the integrated main source, build `vc-21ae974acec8`, for the Godot 4.6.3 project. Open `project.godot` in Godot.

Includes the current gameplay, animated characters, materials, fog/occlusion, construction presentation, cargo return, tutorial, mobile controls and worker feedback. Two additional recovery fixes cancel targeting when the final selected unit dies and keep the final finger of a camera gesture from changing a construction preview.

F12 gameplay screenshots are written to the writable `user://screenshots/` directory. Storage failures are reported, and missing optional build manifests are labelled explicitly.

## Verification status

Tested source `861ca5fa35e01b6a7fa96da1b2457ceea1b3c57c`, game tree `bc86e0554eee81d3aad007551367ac3372361d47`. Includes the opening menu, contextual touch, visible compact Stop and terrain update.

260 headless controlled assertions across eight suites and two byte-identical Web exports passed in [run 42991393471](https://github.com/penny323mo/valley-crown/actions/runs/42991393471). Actual 320×640 and 390×844 Chrome emulated-touch menu, cancel/resume, direct movement/gather and natural construction Stop/resume flows passed in [run 42991819423](https://github.com/penny323mo/valley-crown/actions/runs/42991819423), with screenshot review and strict network/cleanup gates. These are not physical-phone, full combat or victory acceptance. This later README update does not change tested runtime bytes.

`python3 -B tools/stamp_build.py --dry-run` computes deterministic pre-import runtime identity. Import-generated UID sidecars are inventoried separately; do not restamp merely because import generated them. Existing UID files remain unchanged.

Fixtures in `tests/` include synthetic handlers and controlled states. They do not replace natural-play or device acceptance. Weapon/tool/shield grip corrections are not included. Public served-byte verification is separate from browser behavior.

## Artwork and licensing

Editable Blender files, interchange GLBs, native scenes and textures are retained. The existing native `.scn` files are the game assets; do not regenerate them merely to run the project. The authoring generator requires a separately supplied upstream input manifest and source files. Those inputs are not bundled here.

Keep `art/.gdignore` and the Web export exclusions. Font, Godot, Quaternius and KayKit notices are included. See `THIRD_PARTY_NOTICES.txt`.
