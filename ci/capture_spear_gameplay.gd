extends SceneTree
## Controlled actors in the real normal map, using production simulation/presenter.
## Never an ordinary recruitment/playthrough, input-device or performance test.
## No direct animation seek, damage, tick call, camera edit or actor teleport.
const SCENARIO := "native_controlled_rts_spear_v1"
const FIXED_FPS := 20
const SUBJECT_START := Vector3(-21.5,0,28.5)
const SUBJECT_DESTINATION := Vector3(-21.5,0,26.5)
const OPPONENT_POSITION := Vector3(-20.25,0,26.5)
const EXPECTED_FOCUS := Vector3(-25,0,24)
const BASE_BUILD := "vc-43276605e0fb"
const BASE_ASSET := "a3c93a0cdf95d6bf049140c384841ecd59c7fc5933ebd53fd9619f16ca9bab89"
# Disabled draft: exact new native artifact and derived build must be reviewed.
const CANDIDATE_BUILD := "UNBOUND_CANDIDATE"
const CANDIDATE_ASSET := "UNBOUND_NATIVE_OUTPUT"
var game
var destination: String
var build: String
var width: int
var height: int
var subject_id := -1
var opponent_id := -1
var opponent_spawn_tick := -1
var attack_event: Dictionary = {}
var hit_event: Dictionary = {}
var records: Array = []
var commands: Array = []
var mutations: Array = []
var failed := false

func _initialize(): call_deferred("run")
func require_ok(value: bool, reason: String) -> bool:
	if not value:
		failed=true;push_error(reason);quit(1)
	return value
func v3(v: Vector3) -> Array: return [v.x,v.y,v.z]
func xform(t: Transform3D) -> Array: return [v3(t.basis.x),v3(t.basis.y),v3(t.basis.z),v3(t.origin)]
func rect(r: Rect2) -> Array: return [r.position.x,r.position.y,r.size.x,r.size.y]
func observed() -> Dictionary: return game.faction_views[0].records()
func pose() -> Dictionary: return game.visual_evidence_snapshot().get("live",{}).get(str(subject_id),{})
func controller(): return game.character_presenter.controllers.get(subject_id)
func running() -> bool:
	return not failed and not game.test_mode and game.ai_enabled and not game.paused and not game.game_over and game.application_focused and not game.application_suspended
func camera_unchanged() -> bool:
	return game.camera_focus==EXPECTED_FOCUS and game.camera.position==EXPECTED_FOCUS+Vector3(19,25,23) and game.camera_zoom==30.0 and game.camera.size==30.0 and game.camera.projection==Camera3D.PROJECTION_ORTHOGONAL and game.camera.keep_aspect==Camera3D.KEEP_HEIGHT and is_equal_approx(game.camera.near,0.1) and game.camera.far==120.0
func advance():
	await process_frame
	await RenderingServer.frame_post_draw
	# All state queries and PNG capture now describe the same completed frame.
	require_ok(running() and camera_unchanged() and absf(game.get_process_delta_time()-.05)<1e-8,"Normal process or frozen camera changed")
func frames(count: int):
	for i in count:
		await advance()
		if failed:return
func public_record(id: int) -> Dictionary:
	var source: Dictionary=observed().get(id,{})
	if source.is_empty():return {}
	var result: Dictionary={}
	for key in ["id","kind","team","category","owned","alive","remembered","hp","max_hp","state","visual_yaw","visual_action_yaw","visual_moving","visual_action","visual_attack_ready","visual_anticipation","visual_attack_tick","visual_hit_tick","last_seen_tick"]:
		if source.has(key):result[key]=source[key]
	result.position=v3(source.pos)
	if source.has("path"):result.path_points=source.path.size()
	return result
func pair_state(id: int) -> Dictionary:
	if id<0:return {}
	var e: Dictionary=game._get_entity(id)
	return {"id":id,"kind":e.kind,"team":e.team,"alive":e.alive,"position":v3(e.pos),"hp":e.hp,"state":e.state,"target":e.target,"cooldown_ticks":e.cooldown_ticks,"last_damage_tick":e.last_damage_tick,"path_points":e.path.size(),"body_yaw":e.body.rotation.y}
func event_record(e: Dictionary) -> Dictionary:
	if e.is_empty():return {}
	var result: Dictionary={}
	for key in ["attack_id","release_tick","attacker_id","target_id","damage"]:result[key]=e[key]
	result.origin=v3(e.origin);result.endpoint=v3(e.endpoint)
	return result
func pair_events() -> Array:
	var result: Array=[]
	for id in range(1,game.attack_ledger.next_attack_id()):
		var e: Dictionary=game.attack_ledger.event(id)
		if e.attacker_id in [subject_id,opponent_id] or e.target_id in [subject_id,opponent_id]:result.append(event_record(e))
	return result
func submit_order(id: int, target: int, point: Vector3, team: int):
	var data := {"ids":[id],"target":target,"position":point,"command_id":"spear-fixture-"+str(commands.size())}
	game._submit("order",data,team)
	commands.append({"type":"order","ids":[id],"target":target,"position":v3(point),"team":team,"tick":game.tick_count,"sequence":game.command_sequence,"command_id":data.command_id})
func visible_subject() -> bool:
	var c=controller()
	var r: Dictionary=observed().get(subject_id,{})
	if c==null or r.is_empty() or not r.owned or not r.alive or not c.rig.is_visible_in_tree():return false
	var point: Vector2=game.camera.unproject_position(r.pos+Vector3(0,.8,0))
	return game.camera.is_position_in_frustum(r.pos+Vector3(0,.8,0)) and game._box_point_in_world(point)
func capture(label: String, expected_clip: String) -> bool:
	if not require_ok(visible_subject() and pose().get("clip","")==expected_clip and DisplayServer.get_name()=="X11","Expected real visible production clip missing"):return false
	var image: Image=root.get_texture().get_image()
	if not require_ok(image!=null and not image.is_empty() and image.get_size()==Vector2i(width,height),"Missing native framebuffer"):return false
	var name := "%03d-%s.png"%[records.size(),label]
	var path: String=destination.path_join(name)
	if not require_ok(image.save_png(path)==OK,"Cannot save original framebuffer"):return false
	var c=controller()
	var actor: Dictionary=game._get_entity(subject_id)
	var poses: Array=[{"node":".","snapshot":game.visual_evidence_snapshot()}]
	var own: Array=[]
	for r in observed().values():
		if r.owned and r.category=="unit":own.append(public_record(r.id))
	var item := {"image":name,"image_sha256":FileAccess.get_sha256(path),"label":label,"scenario":SCENARIO,"capture_kind":"native_controlled_rts_spear",
		"build":build,"version":game.Rules.VERSION,"game_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"rules_sha256":FileAccess.get_sha256("res://scripts/rules.gd"),
		"spear_asset_sha256":FileAccess.get_sha256("res://assets/mature/models/spearman_action.scn"),"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),
		"rendering_method":RenderingServer.get_current_rendering_method(),"rendering_driver":RenderingServer.get_current_rendering_driver_name(),"adapter_name":RenderingServer.get_video_adapter_name(),"adapter_vendor":RenderingServer.get_video_adapter_vendor(),
		"utc":Time.get_datetime_string_from_system(true,true),"unix_time":Time.get_unix_time_from_system(),"monotonic_usec":Time.get_ticks_usec(),"process_frame":Engine.get_process_frames(),
		"game_tick":game.tick_count,"game_seconds":game.game_time,"game_frame_counter":game.frame_counter,"fixed_fps":FIXED_FPS,"observed_process_delta_seconds":game.get_process_delta_time(),
		"framebuffer":[width,height],"logical_viewport":[root.get_visible_rect().size.x,root.get_visible_rect().size.y],"content_scale_factor":root.content_scale_factor,
		"test_mode":game.test_mode,"ai_enabled":game.ai_enabled,"snapshot":game._snapshot(),"selected":game.selected.duplicate(),"own_units":own,"economy_audit_ok":game.economy.audit().ok,
		"subject":public_record(subject_id),"opponent":public_record(opponent_id),"subject_authority":pair_state(subject_id),"opponent_authority":pair_state(opponent_id),"pair_events":pair_events(),"animation_poses":poses,
		"camera":{"focus":v3(game.camera_focus),"zoom":game.camera_zoom,"projection":game.camera.projection,"keep_aspect":game.camera.keep_aspect,"size":game.camera.size,"near":game.camera.near,"far":game.camera.far,"transform":xform(game.camera.global_transform)},
		"production_transforms":{"unit":xform(actor.node.global_transform),"body":xform(actor.body.global_transform),"rig":xform(c.rig.global_transform),"skeleton":xform(c.skeleton.global_transform),"rig_local":xform(c.rig.transform),"skeleton_local":xform(c.skeleton.transform)},
		"player":{"assigned_clip":c.player.assigned_animation,"current_clip":c.player.current_animation,"actual_seconds":c.player.current_animation_position,"paused":not c.player.is_playing(),"controller_seconds":c.playhead,"transition_time":c.transition_time,"one_shot":c.one_shot},
		"subject_screen":[game.camera.unproject_position(actor.pos+Vector3(0,.8,0)).x,game.camera.unproject_position(actor.pos+Vector3(0,.8,0)).y],
		"hud":{"top":rect(game.hud_top.get_global_rect()),"bottom":rect(game.hud_bottom.get_global_rect()),"resources":game.top_resources.text,"selection_title":game.selection_title.text,"selection_detail":game.selection_detail.text,"time":game.time_label.text},
		"limitations":["Controlled added actors and initial opponent cooldown; not ordinary recruitment/play", "Real unchanged RTS camera/map/HUD, native software OpenGL; not Web or physical phone", "Four event-selected samples, not continuous motion or measured FPS", "Frustum/UI bounds do not certify depth-visible spear pixels; raw images require visual review"]}
	var file:=FileAccess.open(destination.path_join(name+".json"),FileAccess.WRITE)
	if not require_ok(file!=null,"Cannot save provenance"):return false
	file.store_string(JSON.stringify(item,"  ")+"\n");file.close();records.append(item)
	print("NATIVE_SPEAR_FRAME ",label," tick=",game.tick_count," clip=",expected_clip)
	return true
func wait_for(stage: String, maximum: int) -> bool:
	for i in maximum:
		await advance()
		if failed:return false
		var r: Dictionary=observed().get(subject_id,{})
		if not require_ok(not r.is_empty() and r.alive,"Controlled subject disappeared"):return false
		var p: Dictionary=pose()
		if stage=="walk" and p.get("clip","")=="walk" and r.get("visual_moving",false) and r.pos.distance_to(SUBJECT_START)>=.4:return true
		if stage=="arrival" and r.get("state","")=="idle" and not r.get("visual_moving",true) and r.pos.distance_to(SUBJECT_DESTINATION)<=.2:return true
		if stage in ["attack","hit"]:
			if not require_ok(observed().has(opponent_id) and observed()[opponent_id].alive and game.tick_count<opponent_spawn_tick+19,"Controlled combat visibility/lifetime/window failed"):return false
			for e in pair_events():
				if stage=="attack" and e.attacker_id==subject_id and e.target_id==opponent_id:
					if not require_ok(e.release_tick==game.tick_count and e.release_tick==opponent_spawn_tick+2 and p.get("clip","")=="attack" and p.get("attack_release_tick",-1)==e.release_tick and observed()[opponent_id].hp==60-e.damage and absf(float(p.get("seek_seconds",-1))-.61)<1e-7 and absf(controller().player.current_animation_position-.61)<1e-7,"Missed authoritative subject release"):return false
					attack_event=e;return true
				if stage=="hit" and e.attacker_id==opponent_id and e.target_id==subject_id:
					if not require_ok(e.release_tick==game.tick_count and e.release_tick==opponent_spawn_tick+10 and p.get("clip","")=="hit" and p.get("hit_tick",-1)==e.release_tick and r.hp==60-e.damage and absf(float(p.get("seek_seconds",-1))-.05)<1e-7 and absf(controller().player.current_animation_position-.05)<1e-7,"Missed authoritative received hit"):return false
					hit_event=e;return true
	return require_ok(false,"Controlled stage not reached: "+stage)
func run():
	var args:=OS.get_cmdline_user_args()
	if not require_ok(args.size()==4,"Expected output/build/width/height"):return
	destination=args[0];build=args[1];width=int(args[2]);height=int(args[3])
	if not require_ok(build in [BASE_BUILD,CANDIDATE_BUILD] and Vector2i(width,height) in [Vector2i(390,844),Vector2i(844,390)],"Unbound build or dimensions"):return
	var wanted: String=BASE_ASSET if build==BASE_BUILD else CANDIDATE_ASSET
	if not require_ok(wanted.length()==64 and FileAccess.get_sha256("res://assets/mature/models/spearman_action.scn")==wanted,"Unbound native spear"):return
	root.size=Vector2i(width,height);root.content_scale_factor=1.0
	game=load("res://main.tscn").instantiate();root.add_child(game)
	if not require_ok(game.Rules.BUILD_ID==build,"Source identity mismatch"):return
	await frames(12)
	if failed:return
	var subject: Dictionary=game._spawn("spearman",0,SUBJECT_START)
	subject_id=subject.id
	mutations.append({"operation":"controlled_spawn","kind":"spearman","team":0,"id":subject_id,"position":v3(SUBJECT_START),"tick":game.tick_count})
	await frames(4)
	if failed or not capture("idle","idle"):return
	submit_order(subject_id,-1,SUBJECT_DESTINATION,0)
	if not await wait_for("walk",40):return
	if not capture("walk","walk"):return
	if not await wait_for("arrival",60):return
	for i in 20:
		if game.tick_count%20==1:break
		await advance()
		if failed:return
	if not require_ok(game.tick_count%20==1,"Missing deterministic combat window"):return
	var opponent: Dictionary=game._spawn("spearman",1,OPPONENT_POSITION)
	opponent_id=opponent.id;opponent.cooldown_ticks=10;opponent_spawn_tick=game.tick_count
	mutations.append({"operation":"controlled_spawn","kind":"spearman","team":1,"id":opponent_id,"position":v3(OPPONENT_POSITION),"tick":game.tick_count,"initial_cooldown_ticks":10})
	# Visibility is refreshed by the next ordinary tick, before any release.
	# Both actors acquire the in-range opponent via normal DEFEND stance.
	if not await wait_for("attack",12):return
	if not capture("attack-release","attack"):return
	if not await wait_for("hit",12):return
	if not capture("received-hit","hit"):return
	var report:={"passed":true,"scope":"native_controlled_scene_combat","build":build,"scenario":SCENARIO,"frame_count":records.size(),"frames":records,"fixed_fps":FIXED_FPS,"commands":commands,"fixture_mutations":mutations,"attack_event":attack_event,"hit_event":hit_event,"opponent_spawn_tick":opponent_spawn_tick,
		"not_verified":["ordinary unit recruitment or playthrough","physical phone/touch/Web/FPS","continuous motion","full spear depth visibility","art acceptance"]}
	var file:=FileAccess.open(destination.path_join("capture-report.json"),FileAccess.WRITE)
	if not require_ok(file!=null,"Cannot save report"):return
	file.store_string(JSON.stringify(report,"  ")+"\n");file.close();quit(0)
