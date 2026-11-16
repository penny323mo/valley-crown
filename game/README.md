# Idle-worker recovery navigation candidate (source only)

The shortcut menu now shows the current number of eligible idle villagers and a next-worker action. It cycles stable owned IDs, selects one worker and focuses the camera; it never assigns work or cancels the worker's orders. Carrying cargo and terminal work-route status remain eligible when genuinely idle, so the player can inspect and recover them. Active/pending routes and individually queued unit/build orders are excluded. The separate select-all-idle action remains available.

An unchanged-width "idle" cue occupies the existing menu caption only when no attack alert has priority. No new top-bar control is added. Roster/target changes retire held touches and native mouse presses, with exact revalidation at activation. The per-match cursor resets on a new match; navigation is allowed while paused, but not after the match or during focus loss/suspension.

Source/data/grammar checks only. Actual small-screen layout, camera focus, touch routing and game execution remain unrun under the existing holds. No runtime, balance, new screenshot or release acceptance is implied.

---

# AI zero-worker population recovery candidate (source only)

If the last villager is lost while paid military reservations fill population, the AI can cancel one exact paid military queue item to make room for an affordable replacement villager. Prefer an unstarted item, then stable producer/queue IDs. Emergency replacement may use an ordinary keep queue slot up to its existing five-item maximum; other AI production keeps its usual two-item policy. Existing exact refund checks still own cancellation; the next AI turn reads actual bank and population before ordinary training. No live troop is removed and no quoted resource is pre-credited.

This is deliberately one-slot recovery only. It does nothing with a living/queued villager, existing free capacity, insufficient post-refund food, a full keep queue that the selected cancellation cannot open, or population overage requiring multiple cancellations. It cannot guarantee worker birth through blocked exits or resolve a completely live military population. Existing research-funding recovery, repair, army, population, training, movement and economy rules remain unchanged.

Source/data/grammar checks and an unrun controlled fixture are not natural battle, actual engine, phone, rendering or deployment acceptance.

---

# AI post-battle keep recovery candidate (source only)

After its keep takes damage, the AI can borrow one eligible empty-handed worker to perform the existing paid repair task, once the five-second damage lockout has elapsed and no currently observed hostile unit is inside the existing home-threat band. It preserves two food workers, does not interrupt construction/delivery/carrying workers, and prefers idle workers then distance/ID. Active repair is claimed before other economy jobs, preventing policy reassignment from repeatedly resetting the one-second paid work interval.

The AI keeps one wood in its current policy budget for the next ordinary repair payment. This is not a ledger reservation or grant. Actual1wood/5HP, one eligible on-site worker per tick, damage lockout, route limits, bank validation and Stop remain unchanged. A terminal repair route gets an ordinary Stop without fresh search budget. Empty-handed availability is conservative; no guaranteed recovery or AI balance claim is made. Own last-damage timing is projected only for the owner, not to opponents.

Source/data/grammar and prepared unrun fixture only; engine, natural-match, phone and release acceptance are pending. All prior patrol/queue/squad/raid features remain in this exact derivative.

---

# Two-point military patrol candidate (source only)

An explicit Patrol action sends military units between their command-time start and a chosen ground endpoint. Each unit keeps its own origin and resolved endpoint. While walking, the same non-pursuit advance rule pauses for currently observed hostiles already inside weapon range and fires through the unchanged attack authority. When clear, patrol resumes. Normal ground taps remain one-way MOVE; villagers retain their current work. Stop, defend or a replacement order retires the patrol.

Automatic reversal occurs only at actual arrival and does not grant a new initial search, clear retry/failure history, erase a terminal failure or reset a cooldown. Subsequent endpoint resolution is limited to its two-cell neighborhood; no free or distinct endpoint stops the patrol. Existing path/traffic safety gates still apply, and a patrol can stop when those limits are reached. No AI policy, damage, economy or progression change. Source/data/grammar only: genuine movement, combat, touch and render acceptance remain pending.

---

# Exact production queue control candidate (source only)

Each selected producer exposes individual queued units/research in its existing horizontal action strip, with the ledger's actual resource refund and the started item's remaining time. Cancellation binds the permanent queue ID rather than its changing position. If that item completed/disappeared or its refund changed after display, a stale cancellation cannot remove its successor or accept a reduced refund. Pending duplicate taps are suppressed, while the authoritative queue-ID check prevents repeated refunds.

Legacy cancel-last remains for internal AI/tests. Paid ledger rules, 75%-whole-unit started refunds, training time, population reservation and research unlocks are unchanged. UI is source/data/grammar verified only; actual touch, engine production and rendering are pending.

---

# Local raid-escort tactics candidate (source only)

Active AI raid escorts can engage currently observed nearby hostile units instead of ignoring all defenders on the way to the enemy keep. Existing weapon range takes priority, followed by the actual unit counter bonus and a stable current-target preference. The unit's public sight radius bounds local interception. Siege retains the keep objective. Once an interception ends, escorts return to the observed keep or its legitimate last-known ground location, never an unseen target.

Home defense, muster threshold, paid production, raid cadence, retreat rules, path budgets and combat settlement are unchanged. Every tactical choice submits the ordinary command path. This candidate is source/data/grammar checked only, not a real battle, balanced AI, engine or live-release acceptance.

---

# Military squad selection candidate (source only)

Three match-local military groups can be saved and recalled in the existing scrollable shortcut menu. Saving explicitly replaces that group with the selected living own military units; workers and buildings are excluded. Recall filters casualties, selects survivors and focuses their first ID without issuing any order. It can be followed by ordinary contextual move/attack or the separate advance command. The same unit may belong to several groups. Slots clear on a new match, not on pause. Nothing persists after closing the game.

UI members are bound at display and revalidated at activation. Changes retire held touch/mouse, and stale presses cannot operate on a replacement group. This is an isolated source candidate, not a live or engine-tested release.

---

# Local non-pursuit military advance candidate

An explicit military-only advance command retains ordinary destination/path state, pauses for visible hostiles already inside weapon range, fires through existing authority, and continues when the encounter clears. No pursuit, hidden-target lookup, route restart or renewed retry allowance. Normal contextual MOVE and worker orders are unchanged. Terminal routes do not acquire targets. A deliberately held combat tick is excluded only from elapsed traffic-stall/parking clocks. New control is in the existing action strip, not another pinned phone button. Source-only; native combat/touch/render and deployment remain unrun.

## Prior candidate retained verbatim

# Local complete-match report candidate

A read-only after-action report freezes actual player training/completion/combat-loss commits and resource ledger values after the established match result. It excludes setup production, incomplete/cancelled queues and voluntary demolitions from combat losses. Four report pages, bounded phone layout, explicit ended-report touch scrolling and return from the main menu preserve ended tick/outcome. No save system, opponent hidden data or simulation authority. Source/data/grammar only; native fixtures and visual acceptance remain unrun. No publication or backup.

## Prior candidate record, retained verbatim

# Local owned-under-attack navigation candidate

Actual settled positive damage to own units/buildings creates a bounded, expiring location reminder. The existing shortcut menu changes its same-size label to 受襲; an explicit menu action focuses the recorded own victim position, never the attacker. No automatic camera, selection or game commands. Same-area repeated attacks are deduplicated; acknowledged areas stay quiet until twelve simulation seconds without a hit. Held UI ownership is invalidated if the destination changes. Source/data/grammar only; native combat and touch remain unrun. No engine, publication or backup.

## Prior candidate record, retained verbatim

# Local natural-resource rally feature candidate

The keep's existing rally mode can target a currently visible natural resource. Normal paid newborn villagers receive an ordinary queued gather command from current faction knowledge; missing or remembered targets fall back to the accepted ground point without hidden-world lookup. Command execution still rejects targets lost before execution. Scouts/military use ground routing; ground replacement and Clear remove resource identity. Existing costs, training times, farm ownership and path limits remain unchanged. Source/data/grammar only; paid native gather fixture ENGINE_UNRUN. No engine, publication or backup.

## Prior candidate record, retained verbatim

# Local AI research-funded worker recovery candidate

When no living or queued worker remains, a sole paid keep research item can be cancelled through the ordinary command path only if its quoted refund restores an otherwise unaffordable villager and a population slot exists. The AI returns without spending the quote; the next policy turn reads actual refunded funds. Normal research, military queues, refund rates and production time remain unchanged. Source/data/grammar only; paid-recovery native fixture ENGINE_UNRUN. No engine, publication or backup.

## Prior candidate record, retained verbatim

# Local AI retreat-route candidate

A military AI changing from an exact failed explicit ATTACK to a genuinely different resolved ground destination can retire only that old static frontier. Normal MOVE, owned/observed destination selection, search/failure/retry limits and cooldown remain authoritative. LIMIT, stale proof, automatic attacks, old MOVE and aliases are not reopened. Source/data/grammar only; native bounded-search fixture ENGINE_UNRUN. Prior unrun retreat-completion fixture ID alignment corrected explicitly. No engine, deployment or permanent backup.

## Prior candidate record, retained verbatim

# Local AI retreat-completion candidate

A retreating survivor already within the existing home band no longer retains an unbounded explicit attack or outbound move after raid membership is cleared. The AI submits an ordinary Stop before the next movement phase. Existing automatic STOP/DEFEND combat, home-bound movement, distant recall and current home-threat priority remain unchanged. No free action execution, cooldown reset, path-budget relaxation or hidden enemy lookup. Source/data/grammar only; native intent fixture ENGINE_UNRUN. No engine, deployment or permanent backup.

## Prior candidate record, retained verbatim

# Local AI worker-recovery candidate

After worker losses, an AI with fewer than three living-plus-queued villagers prioritizes a normally paid replacement only when its current AI budget can afford one and reserved population leaves a slot. This matches the existing two-food-worker reservation plus one possible builder. Unaffordable food infrastructure, full-population housing, and three-or-more-worker progression remain unchanged. No free unit, economic credit, queue bypass or path-budget change. Native attrition-to-paid-birth-to-deposit fixture is ENGINE_UNRUN; source/data/grammar only. No engine, publication or permanent backup.

## Prior candidate record, retained verbatim

# Local minimap touch-ownership candidate

A second touch reaching the minimap no longer teleports the camera while a world/UI gesture is already owned. Only a tracked sole non-gesture touch can recenter; mouse mapping, normal tap mapping/clamps, and all command/combat behavior are unchanged. Source/data/grammar checks only; native regression is ENGINE_UNRUN. No engine, publication, physical-phone acceptance or backup.

## Prior candidate record, retained verbatim

# Local action-touch lifetime candidate

Unrelated unit deaths and resource depletion no longer destroy an unchanged selected action button beneath a held touch. Selected deaths still invalidate controls; existing queue, research, completion and layout key changes retain their safety rebuild. No new world command or gesture rule. Source/data/grammar only; native fixture is ENGINE_UNRUN. No publication, engine execution, phone validation or permanent backup.

## Prior candidate record, retained verbatim

# AI military attack handoff, 2026-11-12

Build: vc-bd949ac28648. NEW local source candidate over immutable vc-832cb097d83e, not deployed. A genuinely different accepted AI military attack can retire the old attack's completed static NO_PATH proof when its observed target is already in range or resolves to a different known-clear goal. The ordinary order advances its epoch once. All retry timestamps, failures, counters and next-attempt gates remain intact.

Same-target orders, failed-goal aliases outside range, LIMIT_REACHED, traffic failures and stale request/revision proofs do not rearm. Refusing rearm does not discard a valid attack order. No old enemy's hidden position or survival is consulted. Player-command behavior is unchanged. This is a narrow old-ATTACK handoff, not generic AI route recovery. Source/data/grammar and prepared synthetic native checks are not runtime, natural battle, render or phone acceptance. Existing engine/publication/backup holds remain in force.

## Prior candidate record, retained verbatim

# Archer remembered-site inspection, 2026-11-12

Build: vc-832cb097d83e. NEW local source candidate over immutable vc-45b409c6a9f5, not deployed. An archer pursuing an unobserved building first seeks a clear firing slot that can reveal its remembered center, without requiring a vacant melee perimeter. Ordinary range resumes immediately upon observation. If the remembered site is visible but the target remains unobserved, the existing close-inspection rule applies without granting hidden death knowledge. Diagonal perimeter points outside that threshold are excluded.

Observed/default approach, siege/cavalry routing, weapon range, sight, damage and scheduler limits are unchanged. Candidate enumeration remains bounded by the existing envelope. Source/data/grammar evidence and prepared synthetic native fixture are not engine, natural-match, rendering or phone acceptance. Engine/publication/backup holds remain in force.

## Prior candidate record, retained verbatim

# Observed moving-target pursuit recovery, 2026-11-12

Build: vc-45b409c6a9f5. NEW local source candidate over immutable vc-ff86c38fe8e3, not deployed. A completed static NO_PATH proof is retired only when the same currently observed enemy unit moves to a genuinely different known-clear pursuit endpoint. Exact request identity, static frontier reason, unchanged known-grid revision, empty route and no pending/traffic work are required. Automatic STOP, hidden targets, same-goal/alias cases and LIMIT_REACHED remain unchanged.

The ordinary scheduler keeps all retry timestamps, failures, counters, next-attempt gates and shared query caps. Source/data/grammar checks and the prepared synthetic native fixture are not engine, real battle, rendering or phone acceptance. Engine/publication/backup holds remain in force.

## Prior candidate record, retained verbatim

# Mobile camera gesture continuity, 2026-11-12

Build: vc-ff86c38fe8e3. NEW source candidate over immutable vc-ff8feb459f84, not deployed. Camera pan keeps ownership when a held finger returns through its original tap-slop circle. Pinch baselines follow the active world-touch pair and press epochs; a released/reused GUI ID cannot contribute a stale world position. Pair changes rebase from stored pre-drag positions instead of jumping the camera or zoom.

Tap thresholds, command selection, build confirmation, zoom limits and simulation remain unchanged. Source/data/grammar checks and prepared synthetic native input tests are not engine, routed-browser or physical-phone acceptance. Existing engine/publication/backup holds remain in force.

## Prior candidate record, retained verbatim

# In-range attack route retirement, 2026-11-12

Build: vc-ff8feb459f84. NEW source candidate over immutable vc-a8d0068d1477, not a live release. A currently observed target inside release range now retires obsolete queued/traffic movement once, so its later stale search cannot cancel the live attack or consume shared route capacity. Attack identity, cooldown/damage, retry timestamps/search counts/failures and next-attempt gate are unchanged. Out-of-range/hidden targets retain the existing pursuit behavior.

Prepared native fixture is ENGINE_UNRUN. Source/data/grammar checks are not Godot type/import/runtime, natural battle, rendered/phone or deployment acceptance. No engine/publication/backup holds were bypassed.

## Prior candidate record, retained verbatim

# DEFEND retarget source candidate, 2026-11-12

Build: vc-a8d0068d1477. NEW isolated candidate over immutable vc-53565de44ae5, not a live release. Completed automatic DEFEND pursuit is now retired even at its anchor, so a different visible target does not inherit the old goal terminal status. Retry timestamps/counters, failure history and next-attempt gates remain intact; STOP and explicit attack completion are unchanged. No search cap, observation policy or balance is relaxed.

Native regression is prepared only. Source/data and grammar checks do not establish Godot type/import/runtime, natural combat, rendering, phone acceptance or deployment. Existing publication/engine holds remain in force.

## Prior reconstructed candidate record, retained verbatim

# New reconstructed quality candidate, 2026-11-12

Build: `vc-53565de44ae5`. This is a NEW implementation based on immutable reconstructed `vc-f38df7db2c32`, not byte-identical recovery of lost `vc-5713cdd9604e` and not a live release.

The retained camera-ground coverage and range-aware archer approach remain unchanged. Seven formerly missing behaviors are now reconstructed: occupied-farm command atomicity; enemy-farm contextual targeting; terminal farm-lease release; damaged-farm contextual gather intent (explicit repair stays repair); terminal-worker AI commitment filtering with existing cargo handoff; early lost-scout replacement after economy/four-defender safeguards; and bounded static failed-exploration recovery with strict command provenance.

Scout recovery binds the failed MOVE's accepted/requested destination and work epoch, not necessarily the eventual A* endpoint. Ordinary later re-snapping can still refuse or fail. It preserves rolling retry/search/traffic limits, finite attempted cells, and existing shared query gates. No hidden enemy knowledge or simulation speed changes.

Farm cleanup preserves cargo, economy conservation and active delivery/WAIT_SLOT leases. AI excludes stopped workers from false work commitments without clearing budgets; only existing visible full/foreign cargo deposit handoff remains eligible. New prepared command/lifecycle fixtures use disclosed synthetic state and are ENGINE_UNRUN, not natural gameplay or routed-device proof.

Source/data and third-party grammar results are recorded separately. No Godot import/type validation, actual gameplay, rendering or physical-phone validation has run for this candidate. Historical c182 advanced-building assets and soot correction remain unchanged; their acceptance does not transfer automatically. Lost intermediate fixture/policy bytes are not recovered: new focused fixtures replace their intended coverage, not their historical validation. No new UID/import descriptor, CI, publication, upload or backup action was performed.

## Historical source README retained verbatim below

The following inherited text describes earlier work as recorded before this reconstruction. Its “current/latest” wording and old build/release links are historical, not claims about this candidate.

---

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

## Farm completion continuation candidate
A completed farm assigns its finishing villager through ordinary farm work. Foreign cargo is deposited first; existing farm occupancy, one-worker yield and bounded path authority remain unchanged. This candidate is source-validated only, not engine-tested or deployed.

## Statically blocked raid recovery candidate
An active AI raid whose entire surviving cohort has exact current exhausted attack frontiers and cannot fire releases its strategic cohort ownership. Existing actor orders/path limits remain untouched; new troops still require normal muster size, cooldown, observed targets and ordinary commands. Source validation only, no natural match/runtime claim.

## Military reinforcement rally candidate
Barracks, range, stable and workshop can explicitly set an advance rally. Newly paid/born troops queue the existing advance command: engage only in range, resume travel, do not pursue. Ordinary ground and town-center resource rallies retain defaults. Later player orders supersede queued birth orders normally. Source candidate only, not engine-tested or deployed.

## Opt-in continuous military production candidate
Military producers can opt into continuous training at the normal per-unit cost. Only empty queues request one ordinary paid train at a time. Resource/population limits wait, without hidden bank reservation. Turning off keeps paid queued units; successful item cancellation also disables repeat. Default off, normal worker/scout/AI production unchanged. Newborn rally remains ordinary. Source candidate only, no engine or release acceptance.
