# Valley & Crown / 霧谷王旗

The integrated game source is in [`game/`](game/). Main is the development source of truth. Current source build: `vc-2fe28116be93`.

The existing [playable website](https://penny323mo.github.io/valley-crown/) still serves `vc-8fcc302051f0`. Integrating source does not certify or deploy a new playable build. The old Web release and rollback archive remain intact.

See [game setup and verification status](game/README.md). This source-only integration uses `[skip ci]` for one commit, so remote CI and deployment do not run. Local source checks are not Godot, browser or iPhone validation.

The existing Pages workflow is unchanged and still publishes the retained old release on subsequent main pushes or manual dispatch. Review its release-trigger behavior before the next development push. A new playable release needs a validated export and release inputs.
