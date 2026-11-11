# Valley & Crown / 霧谷王旗

The integrated game source is in [`game/`](game/). Main is the development source of truth. Current source and Web beta build: `vc-dd795d96905c`.

Play the updated [public beta](https://penny323mo.github.io/valley-crown/builds/vc-dd795d96905c/) or visit the [game website](https://penny323mo.github.io/valley-crown/).

This release is bound to game source commit `c5b78df4dab1e1f58f83bc2d8678512ddc628045` and game tree `c133ed816d338bfabab2ae617bee917f4080799b`. Native portrait interfaces and the house-construction flow passed. Two byte-identical repeat Web exports from one clean import passed in [export run 42962521219](https://github.com/penny323mo/valley-crown/actions/runs/42962521219).

Browser smoke passed for desktop 1440×900 in [run 42966442322](https://github.com/penny323mo/valley-crown/actions/runs/42966442322) and portrait 390×844 with emulated touchscreen taps in [run 42966100270](https://github.com/penny323mo/valley-crown/actions/runs/42966100270). Checks include loading, pause/resume, menu dismissal, selection, repeated cancellation and no-spend house previews. Desktop training debit/cancellation/refund also passed. Some portrait checks still used keyboard input and synthetic touchcancel.

The release manifest records exact asset hashes and scoped evidence. Gather/deposit, training completion, combat, long-match balance, audible audio and physical iPhone/Android acceptance remain unverified. Browser tests used the exact export on a fresh hosted VM; public served bytes are verified separately after deployment. This is an incremental tested beta, not full-game acceptance.

The Pages deployment retains its original triggers, permissions, concurrency and deploy mechanism. Release inputs are pinned to the verified current candidate. The prior desktop rollback archive remains available.
