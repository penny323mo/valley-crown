extends SceneTree
## Controlled native contract, not a natural match or physical-phone test.
const Status=preload("res://scripts/worker_idle_status.gd")
var checks: Array=[]
var game
func _initialize(): call_deferred("run")
func check(name: String, passed: bool):
	checks.append({"name":name,"pass":passed})
	if not passed: push_error(name)
func reason(worker: Dictionary, records: Dictionary={}, pending=false) -> String:
	return Status.missing_resource(worker,records,pending)
func publish():
	game._publish_faction_views(); game._update_hud()
func run():
	var worker={"owned":true,"alive":true,"kind":"villager","state":"idle","mode":"WORK","path_request_kind":"work","cargo_milli":0,"path_pending":false,"path_status":"IDLE","gather_type":"food"}
	check("explicit food intent",reason(worker)=="food")
	var wood=worker.duplicate(); wood.gather_type="wood"
	check("explicit wood intent and distinct label",reason(wood)=="wood" and Status.label("food")!=Status.label("wood"))
	for patch in [{"owned":false},{"alive":false},{"kind":"scout"},{"state":"gather"},{"state":"deliver"},{"mode":"STOP"},{"mode":"DEFEND"},{"path_request_kind":"point"},{"cargo_milli":1},{"path_pending":true},{"gather_type":""}]:
		var changed=worker.duplicate(); changed.merge(patch,true)
		check("exclude "+str(patch),reason(changed).is_empty())
	for status in ["NO_PATH","LIMIT_REACHED","NO_WORK","QUEUED"]:
		var changed=worker.duplicate(); changed.path_status=status
		check("exclude terminal or pending path "+status,reason(changed).is_empty())
	check("pending own order suppresses stale guidance",reason(worker,{},true).is_empty())
	var berry={"category":"resource","alive":true,"kind":"berry","remembered":true}
	check("stale fog memory still counts as known",reason(worker,{1:berry}).is_empty())
	check("known food does not suppress wood",reason(wood,{1:berry})=="wood")
	for kind in ["pine","oak"]:
		check("known "+kind+" suppresses wood",reason(wood,{1:{"category":"resource","alive":true,"kind":kind}}).is_empty())
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	game.paused=false; game.application_focused=true; game.application_suspended=false
	var owned: Dictionary=game._first(0,"villager")
	var source: Dictionary=game._nearest_known_resource(owned.pos,"food",0)
	check("opening source exists",not source.is_empty())
	if source.is_empty(): finish(); return
	game._order(owned,"gather",source.id)
	# Deliberately controlled no-known-resource world. No authority removal:
	# sources remain real and alive but are absent from this faction's knowledge.
	game.visible_cells[0].fill(0); game.faction_views[0].memory.clear()
	game.work_memory[0].resources.clear()
	game._resume_gather(owned); game.selected=[owned.id]; publish()
	check("real resume path retains idle WORK intent",owned.state=="idle" and owned.mode=="WORK" and owned.gather_type=="food")
	check("actual HUD explains absent known food",game.selection_detail.text.contains("無已知糧源") and game.selection_detail.text.contains("探索或落指令"))
	var projected: Dictionary=game.faction_views[0].get_record(owned.id)
	check("real owned projection supplies qualifying fields",reason(projected,game.faction_views[0].records())=="food")
	game.selected=[owned.id,game._first(0,"scout").id]; game._update_hud()
	check("mixed multi selection counts only affected worker",game.selection_detail.text.contains("1 村民無已知採集點"))
	var second: Dictionary={}
	for ent in game.entities:
		if ent.alive and ent.team==0 and ent.kind=="villager" and ent.id!=owned.id: second=ent; break
	# Controlled owned state exercises the actual public projection and mixed HUD.
	second.state="idle"; second.mode="WORK"; second.gather_type="wood"; second.path_request_kind="work"; second.path_status="IDLE"; second.path_pending=false
	game.selected=[owned.id,second.id,game._first(0,"scout").id]; publish()
	check("mixed food wood and generic selection counts two",game.selection_detail.text.contains("2 村民無已知採集點"))
	game._set_stance(second,"STOP"); publish()
	check("STOP excluded from mixed selection",game.selection_detail.text.contains("1 村民無已知採集點"))
	game.selected=[owned.id]; game.touch_command=true; game.compact_ui=true; game._update_hud()
	check("touch target instructions override warning",not game.selection_detail.text.contains("無已知") and game.selection_detail.text.contains("取消"))
	game.touch_command=false; game.box_select_mode=true; game._update_hud()
	check("box instructions override warning",game.selection_title.text=="框選單位" and not game.selection_detail.text.contains("無已知"))
	game.box_select_mode=false; game.build_mode="house"; game._update_hud()
	check("build instructions override warning",game.selection_title.text.begins_with("建造") and not game.selection_detail.text.contains("無已知"))
	game.build_mode=""; publish()
	# Observe an actual berry, then hide it: frozen remembered stock still counts.
	game.visible_cells[0][game._cell_index(source.pos)]=1; publish()
	check("actual observed resource suppresses warning",not game.selection_detail.text.contains("無已知"))
	game.visible_cells[0].fill(0); publish()
	check("actual remembered resource suppresses warning",game.faction_views[0].get_record(source.id).get("remembered",false) and not game.selection_detail.text.contains("無已知"))
	game.faction_views[0].memory.clear(); publish()
	var before: String=game.selection_detail.text
	var before_bank=game.economy.bank_milli(0).duplicate()
	var before_rng: int=game.rng.state
	for i in 8: game._update_hud()
	check("repeated HUD calls do not mutate bank or RNG",game.economy.bank_milli(0)==before_bank and game.rng.state==before_rng)
	# Change hidden authoritative liveness and enemy location, then publish again.
	var hidden: Dictionary=game._get_entity(source.id)
	hidden.alive=false
	var enemy: Dictionary=game._first(1,"villager"); enemy.pos+=Vector3(2,0,0); enemy.gather_type="wood"
	publish()
	check("hidden resource death and enemy intent cannot affect UI",game.selection_detail.text==before)
	hidden.alive=true; publish()
	check("hidden resource return cannot affect UI",game.selection_detail.text==before)
	game._submit("defend",{"ids":[owned.id]}); game._update_hud()
	check("queued non-STOP order suppresses stale guidance",not game.selection_detail.text.contains("無已知"))
	game.commands.clear()
	game._submit("stop",{"ids":[owned.id]}); game._update_hud()
	check("queued stop immediately suppresses stale guidance",not game.selection_detail.text.contains("無已知"))
	game.commands.clear(); game._set_stance(owned,"STOP"); publish()
	check("executed stop with retained gather_type stays generic",owned.gather_type=="food" and not game.selection_detail.text.contains("無已知"))
	game._test_reset(); game.selected=[game._first(0,"villager").id]; publish()
	check("restart has no stale missing-resource guidance",not game.selection_detail.text.contains("無已知"))
	finish()
func finish():
	var failed=checks.filter(func(c): return not c.pass).size()
	var hashes={}
	for path in ["scripts/game.gd","scripts/worker_idle_status.gd","scripts/faction_view.gd","tests/worker_idle_status_contract.gd"]: hashes[path]=FileAccess.get_sha256("res://"+path)
	FileAccess.open("res://reports/worker-idle-status-contract.json",FileAccess.WRITE).store_string(JSON.stringify({"scope":"Controlled native helper/actual resume and HUD contract; not natural match, pixels, balance or physical-phone acceptance","checks":checks,"passed":checks.size()-failed,"failed":failed,"source_sha256":hashes,"engine":Engine.get_version_info()},"  ")+"\n")
	if game: game.free()
	quit(1 if failed else 0)
