# Valley & Crown game source

This is the integrated main source, build `vc-dd795d96905c`, for the Godot 4.6.3 project. Open `project.godot` in Godot.

Includes the current gameplay, animated characters, materials, fog/occlusion, construction presentation, cargo return, tutorial, mobile controls and worker feedback. Two additional recovery fixes cancel targeting when the final selected unit dies and keep the final finger of a camera gesture from changing a construction preview.

F12 gameplay screenshots are written to the writable `user://screenshots/` directory. Storage failures are reported, and missing optional build manifests are labelled explicitly.

## Verification status

Source integrity and the two focused code changes were reviewed. This exact integrated build has **not** been parsed, imported, executed, rendered or exported with Godot, and has no browser or physical-iPhone acceptance. Historical results and screenshots are not validation of this build.

`python3 -B tools/stamp_build.py --dry-run` computes the deterministic runtime identity without changing files. A clean engine import can generate missing UID sidecars and change the identity; inspect that delta and restamp deliberately before running build-bound tests. The two building-damage tests are bound to the current pre-import identity.

The tests in `tests/` cover gameplay contracts and synthetic native input. They are not physical-device checks. Prior to a new playable release, use a suitable runner for import/parser checks, regression tests, ordinary portrait/landscape play, Web export and browser validation. iPhone acceptance requires a real iPhone.

## Artwork and licensing

Editable Blender files, interchange GLBs, native scenes and textures are retained. The existing native `.scn` files are the game assets; do not regenerate them merely to run the project. The authoring generator requires a separately supplied upstream input manifest and source files. Those inputs are not bundled here.

Keep `art/.gdignore` and the Web export exclusions. Font, Godot, Quaternius and KayKit notices are included. See `THIRD_PARTY_NOTICES.txt`.
