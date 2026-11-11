# Source and license notes

The original stable, workshop, watchtower and farm composition and geometry are
authored for Valley & Crown by `tools/build_advanced_building_assets.py`. Existing
original project stone, dark oak, plaster, slate and clay PNGs are reused unchanged
with the established material names, UV scale and restrained faction cloth.
No new public license is granted for original project code/artwork.

Two small donor meshes are actually incorporated, not used as unrelated stand-ins:

- Quaternius Medieval Village MegaKit Standard `Prop_Crate`: 230 source triangles,
  scaled to 0.32 in the stable and 0.34 in the workshop, recoloured/re-UV-mapped to
  the existing project oak material.
- The same pack's `Prop_Chimney2`: 130 source triangles, scaled to
  (0.48, 0.92, 0.48) in the workshop and remapped to project stone.

The copied `.gltf` and `.bin` pairs retain their original bytes. The author reads
only raw POSITION/index data, explicitly rejecting node transforms or unexpected
buffer references. Donor texture references remain in the original source JSON,
but those upstream textures are not needed or redistributed; the game's models
reference the original project textures instead. `art/.gdignore` in the existing
project prevents these source-only files from being imported as runtime assets.

Creator source: https://quaternius.itch.io/medieval-village-megakit
License: CC0 1.0 Universal, https://creativecommons.org/publicdomain/zero/1.0/
The actual included Standard pack notice is preserved verbatim at
`upstream/QUATERNIUS-LICENSE.txt`. Exact donor file hashes are in the delivery
inventory. No paid catalog geometry, paid native source or external texture is used.

The CC0 wagon, generic walls and larger roof-kit pieces were inspected but not
substituted for completed military architecture. The established five original
building meshes were not relabeled or changed. Stable horse-shaped units and
animated siege assets are intentionally absent from this static building set.

`geometry.json` is source geometry metadata, not imported/rendered acceptance.
The glTF front-face convention is counterclockwise. Godot's importer is responsible
for conversion to native mesh conventions; the source does not manually invert
glTF winding. Only a real authorized import/render can validate that conversion.
