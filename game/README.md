# Valley & Crown game source

This is the integrated main source, build `vc-cf764648c52f`, for the Godot 4.6.3 project. Open `project.godot` in Godot.

Includes the current gameplay, animated characters, materials, fog/occlusion, construction presentation, cargo return, tutorial, mobile controls and worker feedback. Two additional recovery fixes cancel targeting when the final selected unit dies and keep the final finger of a camera gesture from changing a construction preview.

F12 gameplay screenshots are written to the writable `user://screenshots/` directory. Storage failures are reported, and missing optional build manifests are labelled explicitly.

## Verification status

Tested runtime source: `677096aaaa5131089971c2ec85b598ad20bd91da`, game tree `dec0eabb654f36c837e68db547d4282bea0754fb`. 34 value-contract and 30 controlled synthetic HUD assertions and two identical Web exports passed in [run 42973027221](https://github.com/penny323mo/valley-crown/actions/runs/42973027221). Natural portrait touch placement, Stop, stable progress and resumed work passed in [run 42977355259](https://github.com/penny323mo/valley-crown/actions/runs/42977355259), including actual screenshots and strict network/cleanup gates. This is emulated Chrome touch, not physical-phone or full-game acceptance. This later README update does not change the tested runtime bytes.

The construction-status helper and read-only QA observations have source review and bounded grammar checks. Revised construction labels were checked against the unchanged shipped font cmap. These checks are not engine execution or rendered-device acceptance.

`python3 -B tools/stamp_build.py --dry-run` computes the deterministic pre-import runtime identity without changing files. Preserve that identity through guarded import. Expected generated UID sidecars are inventoried and hash-bound separately; do not restamp merely because import generated them. Existing UID files must remain unchanged.

The tests in `tests/` include controlled gameplay and HUD fixtures. They are not natural-play or physical-device acceptance. Current browser evidence must distinguish emulated touch from real devices and list untested flows. Public served-byte verification is separate from browser behavior.

## Artwork and licensing

Editable Blender files, interchange GLBs, native scenes and textures are retained. The existing native `.scn` files are the game assets; do not regenerate them merely to run the project. The authoring generator requires a separately supplied upstream input manifest and source files. Those inputs are not bundled here.

Keep `art/.gdignore` and the Web export exclusions. Font, Godot, Quaternius and KayKit notices are included. See `THIRD_PARTY_NOTICES.txt`.
