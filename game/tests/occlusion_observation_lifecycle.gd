extends SceneTree
## PREPARED ONLY. Actual game observation/presenter code, controlled visibility.
## Run only after a guarded-host clean import. Not normal player-flow evidence.
var game
var checks: Array=[]
func _initialize(): call_deferred("run")
func check(label: String, okay: bool, detail={}) -> void:
	checks.append({"name":label,"pass":okay,"detail":detail})
	if not okay: push_error(label+" "+str(detail))
func publish() -> void:
	game._publish_faction_views(); game._update_visuals(0.0)
func known(id: int) -> bool:
	return game.faction_views[0].records().has(id)
func eligible(id: int) -> bool:
	return game.character_presenter.controllers.has(id) and game.character_presenter.controllers[id].occlusion.enabled
func reveal(position: Vector3, value: int) -> void:
	game.visible_cells[0][game._cell_index(position)]=value
func run() -> void:
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	game.paused=false; game.application_focused=true; game.application_suspended=false
	for team in 2: game.visible_cells[team].fill(0)
	publish()
	var enemy: Dictionary=game._first(1,"scout")
	var owned: Dictionary=game._first(0,"scout")
	var original_position: Vector3=enemy.pos
	check("hidden enemy has no record or eligible rig",not known(enemy.id) and not eligible(enemy.id))
	check("hidden authority unit has no rig or overlay",enemy.body.find_children("ObservedActionRig","Node3D",true,false).is_empty() and not enemy.node.visible)
	check("own units remain eligible even outside synthetic vision",known(owned.id) and eligible(owned.id))
	# Reveal through the game's genuine publish boundary, not direct presenter data.
	reveal(enemy.pos,1); publish()
	check("currently observed enemy gets legal proxy and silhouette",known(enemy.id) and eligible(enemy.id) and not enemy.node.visible and game.presentation_nodes[enemy.id].node.visible)
	if not eligible(enemy.id): finish(); return
	var first_controller=game.character_presenter.controllers[enemy.id]
	var first_rig: Node3D=first_controller.rig
	check("enemy rig is owned by presentation proxy not authority",first_rig.get_parent()==game.presentation_nodes[enemy.id].body and first_rig.get_parent()!=enemy.body)
	# Current, actually observable attack presentation may run. This cue-only
	# setup is deliberate; there is no combat order/damage assertion in this test.
	game.unit_action_cues[0][enemy.id]={"attack_tick":game.tick_count}
	publish(); check("observed current release uses attack pose",first_controller.clip=="attack")
	reveal(enemy.pos,0); game.tick_count+=1; publish()
	check("fog removal releases live rig before rendering",not known(enemy.id) and not eligible(enemy.id) and not is_instance_valid(first_rig))
	check("fog removal disables retained controller handles",not first_controller.occlusion.enabled and first_controller.occlusion.owner_rig==null and first_controller.occlusion.overlays.is_empty())
	check("hidden proxy ancestor is hidden",not game.presentation_nodes[enemy.id].node.visible)
	check("hidden enemy units never become remembered records",not game.faction_views[0].memory.has(enemy.id))
	check("hidden action history is purged",not game.unit_action_cues[0].has(enemy.id))
	# Hidden authority movement is allowed by the fixture, but may not refresh the
	# last-seen proxy or leak a new rig before another legitimate observation.
	var last_proxy_position: Vector3=game.presentation_nodes[enemy.id].node.position
	enemy.pos+=Vector3(3,0,0); game.tick_count+=20; publish()
	check("hidden movement never refreshes presentation",not known(enemy.id) and not eligible(enemy.id) and game.presentation_nodes[enemy.id].node.position==last_proxy_position)
	reveal(enemy.pos,1); publish()
	check("reappearance creates a fresh eligible controller",eligible(enemy.id) and game.character_presenter.controllers[enemy.id]!=first_controller)
	if not eligible(enemy.id): finish(); return
	var returned=game.character_presenter.controllers[enemy.id]
	check("reappearance cannot replay hidden attack history",returned.clip=="idle" and returned.last_attack_tick==-1 and not returned.one_shot)
	check("reappearance uses new observed position",game.presentation_nodes[enemy.id].node.position==enemy.pos and enemy.pos!=original_position)
	# Unwitnessed enemy death creates no corpse. A previously seen ID is no grant.
	reveal(enemy.pos,0); publish(); var deaths_before: int=game.character_presenter.corpses.size()
	game._kill(enemy)
	check("hidden death has no witnessed event",game.pending_visual_deaths.is_empty())
	publish(); check("hidden death leaves no corpse or rig",game.character_presenter.corpses.size()==deaths_before and not eligible(enemy.id))
	# Witnessed enemy death may leave a bounded corpse, but never a silhouette.
	var victim: Dictionary=game._first(1,"villager")
	reveal(victim.pos,1); publish(); check("visible victim has eligible rig",eligible(victim.id))
	game._kill(victim); publish()
	check("witnessed death removes live eligibility",not eligible(victim.id) and not known(victim.id))
	check("witnessed death creates exactly one detached visual",game.character_presenter.corpses.size()==deaths_before+1)
	if game.character_presenter.corpses.size()>deaths_before:
		var corpse: Dictionary=game.character_presenter.corpses[-1]
		corpse.controller.occlusion.set_authorized(true)
		check("corpse cannot acquire either occlusion pass",not corpse.controller.occlusion.enabled and not corpse.controller.rig.get_meta("occlusion_authorized"))
		reveal(victim.pos,0); publish()
		check("enemy corpse disappears as its last observed cell enters fog",game.character_presenter.corpses.size()==deaths_before)
	# Own corpse is still visible without enemy-cell authorization and expires by
	# its bounded animation lifecycle; it cannot become an occlusion candidate.
	game._kill(owned); publish()
	check("own witnessed corpse is kept outside synthetic vision",game.character_presenter.corpses.size()==deaths_before+1)
	for i in 100: game.character_presenter.update_deaths(.05,true,func(_p): return false)
	check("own corpse finishes bounded without restoring overlays",game.character_presenter.corpses.size()==deaths_before)
	var snapshot: Dictionary=game._snapshot().duplicate(true); var rng_state: int=game.rng.state
	for i in 5: game._update_visuals(0.0)
	check("occlusion presentation does not change game snapshot or RNG",game._snapshot()==snapshot and game.rng.state==rng_state)
	game._test_reset(); game._update_visuals(0.0)
	check("restart removes corpse and old history",game.character_presenter.corpses.is_empty() and game.pending_visual_deaths.is_empty() and game.unit_action_cues==[{},{}])
	check("restart enemy fog exclusion remains",not eligible(game._first(1,"scout").id))
	finish()
func finish() -> void:
	var failed:=checks.filter(func(c): return not c.pass).size()
	var hashes: Dictionary={}
	for path in ["scripts/game.gd","scripts/faction_view.gd","scripts/observed_character_presenter.gd","scripts/action_character.gd","scripts/observed_occlusion.gd","tests/occlusion_observation_lifecycle.gd"]:
		hashes[path]=FileAccess.get_sha256("res://"+path)
	FileAccess.open("res://reports/occlusion-observation-lifecycle.json",FileAccess.WRITE).store_string(JSON.stringify({"scope":"Actual game observation/presenter code with controlled visibility and event setup; not gameplay/pixel/mobile acceptance","checks":checks,"passed":checks.size()-failed,"failed":failed,"source_sha256":hashes,"engine":Engine.get_version_info()},"  ")+"\n")
	game.free(); quit(1 if failed else 0)
