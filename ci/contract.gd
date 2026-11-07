extends SceneTree
## Actual presenter/authority code with controlled observation, not player-flow or pixel acceptance.
var game
var checks: Array=[]
func _initialize(): call_deferred("run")
func check(label: String,okay: bool) -> void:
	checks.append({"name":label,"pass":okay})
	if not okay: push_error(label)
func reveal(position: Vector3,value: int) -> void:
	game.visible_cells[0][game._cell_index(position)]=value
func run() -> void:
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	game.paused=false; game.application_focused=true; game.application_suspended=false
	var archer: Dictionary=game._spawn("archer",0,Vector3(0,0,0))
	var target: Dictionary=game._spawn("spearman",1,Vector3(2,0,0))
	game._update_vision()
	# Exercise the real successful release gate; do not alter attack/damage timing.
	game.test_mode=false
	var result: Dictionary=game._release_attack(archer,target)
	game.test_mode=true
	check("successful authority release creates exactly one cue",result.applied and game.attack_effects.size()==1)
	var repeated: Dictionary=game._release_attack(archer,target)
	game._replay_attack(result.event)
	check("cooldown failure and exact replay cannot duplicate cue",not repeated.applied and game.attack_effects.size()==1)
	var authority: Dictionary=game._combat_snapshot().duplicate(true)
	var hp: int=target.hp
	var cooldown: int=archer.cooldown_ticks
	var rng_state: int=game.rng.state
	var cue: Dictionary=game.attack_effects[0]
	var beam: Node3D=cue.node
	var transform: Transform3D=beam.transform
	game._update_visuals(0.04)
	check("running cue consumes only visual elapsed time",is_equal_approx(cue.age,0.04))
	game.paused=true
	game._update_visuals(0.5)
	await create_timer(0.16).timeout
	check("gameplay pause cannot expire cue via independent tween",game.attack_effects.size()==1 and is_instance_valid(beam) and is_equal_approx(cue.age,0.04))
	game.paused=false; game.application_focused=false
	game._update_visuals(0.5)
	check("background focus freezes cue age",is_equal_approx(cue.age,0.04))
	game.application_focused=true; game.application_suspended=true
	game._update_visuals(0.5)
	check("suspension freezes cue age",is_equal_approx(cue.age,0.04))
	game.application_suspended=false
	game.discard_return_delta=true
	game._process(15.0)
	check("first stale focus-return frame is discarded by actual process",is_equal_approx(cue.age,0.04) and not game.discard_return_delta)
	var released_endpoint: Vector3=target.pos
	target.pos+=Vector3(12,0,0)
	game._update_visuals(0.01)
	check("target motion cannot move or retarget release cue",beam.transform==transform and cue.endpoint==released_endpoint)
	target.pos=released_endpoint
	game._update_visuals(0.08)
	check("resume retires cue after original bounded visual lifetime",game.attack_effects.is_empty() and not beam.visible)
	check("presentation cannot settle or mutate combat state",game._combat_snapshot()==authority and target.hp==hp and archer.cooldown_ticks==cooldown and game.rng.state==rng_state)
	await process_frame
	check("expired node is actually freed",not is_instance_valid(beam))
	# Loss of current visibility retires permanently, even while paused.
	game._attack_effect(archer,target); beam=game.attack_effects[0].node
	game.paused=true
	reveal(target.pos,0); game.explored_cells[0][game._cell_index(target.pos)]=1
	game._publish_faction_views(); game._update_visuals(0.0)
	check("exploration memory does not retain a cue while paused",game.attack_effects.is_empty() and not beam.visible)
	reveal(target.pos,1); game._publish_faction_views(); game._update_visuals(0.0)
	check("reappearance cannot replay a revoked cue",game.attack_effects.is_empty())
	game.paused=false
	# A hidden endpoint never grants an initial cue; enemy origin is also gated.
	reveal(target.pos,0); game._attack_effect(archer,target)
	check("hidden target suppresses creation",game.attack_effects.is_empty())
	reveal(target.pos,1)
	var enemy_archer: Dictionary={"kind":"archer","team":1,"pos":Vector3(8,0,0)}
	reveal(enemy_archer.pos,0); game._attack_effect(enemy_archer,archer)
	check("hidden attacker suppresses creation",game.attack_effects.is_empty())
	reveal(enemy_archer.pos,1); game._attack_effect(enemy_archer,archer)
	beam=game.attack_effects[0].node
	reveal(enemy_archer.pos,0); game._update_visuals(0.0)
	check("enemy origin losing vision revokes cue",game.attack_effects.is_empty() and not beam.visible)
	# Witnessed lethal endpoints may persist briefly without tracking a live record.
	archer.cooldown_ticks=0; archer.state="attack"; archer.target=target.id
	target.hp=1
	var release_tick: int=game.tick_count
	game.test_mode=false; game._tick(game.Rules.TICK); game.test_mode=true
	beam=game.attack_effects[0].node
	game._update_visuals(0.01)
	check("real tick settles lethal attack while retaining frozen witnessed cue",not target.alive and not game.game_over and game.tick_count==release_tick+1 and game.attack_effects.size()==1 and beam.visible and game.attack_effects[0].endpoint==released_endpoint)
	game._clear_attack_effects(); game._clear_attack_effects()
	check("repeated cleanup is safe and immediately hides nodes",game.attack_effects.is_empty() and not beam.visible)
	# Synthetic burst exercises a hard visual bound without issuing any new hits.
	var visual_target: Dictionary={"kind":"spearman","team":1,"pos":released_endpoint}
	var evicted: Node3D
	for i in game.MAX_ATTACK_EFFECTS+1:
		game._attack_effect(archer,visual_target)
		if i==0: evicted=game.attack_effects[0].node
	check("burst is bounded by match population and hides evicted node",game.attack_effects.size()==game.MAX_ATTACK_EFFECTS and not evicted.visible)
	var terminal_nodes: Array=[]
	for item in game.attack_effects: terminal_nodes.append(item.node)
	game.game_over=true; game._update_visuals(0.0)
	check("terminal state clears all effects without aging",game.attack_effects.is_empty())
	game._attack_effect(archer,visual_target)
	check("terminal state rejects fresh visual effects",game.attack_effects.is_empty())
	await process_frame
	check("burst eviction and terminal cleanup free every node",not is_instance_valid(evicted) and terminal_nodes.all(func(n): return not is_instance_valid(n)))
	game.game_over=false
	game._attack_effect(archer,visual_target); beam=game.attack_effects[0].node
	game._test_reset()
	check("reset removes effect ownership and hides old node",game.attack_effects.is_empty() and not beam.visible)
	await process_frame
	check("reset frees old cue node",not is_instance_valid(beam))
	# Match reload tears down the scene; verify the same exit hook directly.
	var owned: Dictionary={"kind":"archer","team":0,"pos":Vector3.ZERO}
	var endpoint: Dictionary={"kind":"spearman","team":0,"pos":Vector3(2,0,0)}
	game._attack_effect(owned,endpoint); beam=game.attack_effects[0].node
	root.remove_child(game)
	check("scene exit clears effect registry and hides cue",game.attack_effects.is_empty() and not beam.visible)
	finish()
func finish() -> void:
	var failed: int=checks.filter(func(c): return not c.pass).size()
	var hashes: Dictionary={}
	for path in ["scripts/game.gd","scripts/attack_ledger.gd","scripts/rules.gd"]:
		hashes[path]=FileAccess.get_sha256("res://"+path)
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"build":game.Rules.BUILD_ID,"completed":true,"game_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"manifest_sha256":FileAccess.get_sha256("res://reports/build-manifest.json"),"contract_sha256":FileAccess.get_sha256(get_script().resource_path),"source_lock_sha256":FileAccess.get_sha256(get_script().resource_path.get_base_dir()+"/source_lock.json"),"scope":"Controlled observation and actual game code; not pixel/player-flow acceptance","checks":checks,"passed":checks.size()-failed,"failed":failed,"source_sha256":hashes,"engine":Engine.get_version_info()},"  ")+"\n")
	game.free(); quit(1 if failed else 0)
