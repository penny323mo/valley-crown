# Durable Web release storage

The 16 historical Actions inputs consumed by Pages are now backed up as individual
GitHub Release assets. The original artifact ZIP is preserved, not re-exported.
`release-history/WEB_ARCHIVE_CATALOG.json` pins the asset ID, ZIP SHA-256 and the
existing per-file or candidate-metadata SHA-256 trust anchor. Release labels alone
are not trusted. The rollback `vc-bff2dcf4109a` remains its checksum-pinned repo ZIP.

`web_release_archive.py archive` is append-only: validates before upload, never
replaces/deletes a release asset, then independently downloads and verifies it.
`restore` fails closed if a backup is missing; it never falls back to an expiring
Actions artifact. It stages files only after safe ZIP path/type and full hash
validation. This removes the Actions retention dependency; it is not a promise
that an owner cannot delete GitHub Release assets.

Before cutover, run 43561898440 reconstructed all 17 builds (362 site files) using
Release assets only and the original Pages assembly/validators. Result:
990,002,448 bytes. The exact historical raw file hashes are committed in
`release-history/PAGES_ARCHIVE_BASELINE.json`. Pages verifies every historical
`builds/` path against that baseline before publishing and caps total at a
conservative 1,000,000,000 bytes. Landing and play redirects may evolve, but no
historical game/raw asset is modified or removed by this migration.

## Future versions

Do not append another full 60 MB build to this almost-full Pages site. Prepare a
separate suitable host for new versions while keeping these historical paths
intact. A second host must have verified size, access, retention and commercial
use terms. Never assume deployment permalinks are retained indefinitely.

New archives require a catalog entry with its actual build/run/artifact and
trusted file hashes (or metadata hash), then archive + read-back verification.
Pin the resulting ZIP hash and asset ID before production consumers use it.
Never overwrite a catalog record to point an old build name at new bytes. Keep
source manifests/licenses with each build. Do not remove old data to make room.

## Verification

- `python3 -m unittest discover -s scripts -p test_web_release_archive.py -v`
- `python3 scripts/web_release_archive.py plan`
- `python3 scripts/verify_archived_pages.py` in a clean checkout with read token

The complete site verification is separate from gameplay QA. No new gameplay
feature or visual change is claimed by this storage migration.
