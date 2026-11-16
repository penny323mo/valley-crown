# v66 ordinary-command expedition journey

Runtime: vc-08902d1190c7; source 3b418ee2c6957dfdeca707f031faf35c3472c465.
Published PCK SHA-256: c9007f6a5e1d81b8663f4f6bd9b615a42f32e175144b64535a75be9877096479.

The accompanying headless receipt records an autonomous player from normal opening funds. Decisions use owned/currently observed records and public mission landmarks. All economy, construction, production, movement, attacks, deaths and mission transitions run through ordinary commands and full 0.05-second ticks. No units are gifted by the driver, and it does not edit HP, bank, positions, stage or simulation clock.

Result: victory / expedition_complete at tick11157 (557.85 simulated seconds).
Stage transitions: 1860,6654,7501,9339,11157. Paid production: 22 spearmen and6 villagers. Completed:2 barracks and5 houses. Losses:11 spearmen and1 villager. Economy audit passed.

This is automated simulation, not manual playing, physical-phone acceptance, general balance acceptance or a new feature release. Authored mission guards and the disclosed six-unit reinforcement are scenario rules. The engine test_mode suppresses history writes and attack visual effects, not combat authority. An isolated XDG directory and unique temporary history path provide additional protection. No existing player saves are accessed.

ci/capture-v66-natural-expedition.gd preserves this decision algorithm and captures real current state at phase transitions and victory. Its final explicit test_mode/history-nonexistence assertions were added after the recorded headless process had loaded its script, so the receipt is not evidence that those later assertions ran. The native capture workflow runs the final assertions. All native screenshots must be checked against its actual receipt before claiming completion.

Resource guard:2GiB address space,300 CPU seconds,330 wall seconds,3GiB host reserve. The driver itself stops after285 seconds if no outcome has occurred. Failed or incomplete attempts remain failures and are never labelled a win.
