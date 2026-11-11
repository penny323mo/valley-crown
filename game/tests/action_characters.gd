extends SceneTree
const Controller = preload("res://scripts/action_character.gd")
const Presenter = preload("res://scripts/observed_character_presenter.gd")
var checks: Array = []
var evidence: Dictionary = {}
var tool_transitions: Array = []
func _initialize(): call_deferred("run")
func check(label: String, ok: bool, detail = "") -> void:
	checks.append({"name":label,"pass":ok,"detail":detail})
	if not ok: push_error(label+" "+str(detail))
func pose(c) -> Array:
	var result: Array = []
	for bone in c.skeleton.get_bone_count(): result.append(c.skeleton.get_bone_pose(bone))
	return result
func tools(c, action: String) -> Dictionary:
	var active: String={"attack":"axe","gather_wood":"axe","gather_food":"sickle","build":"hammer","repair":"hammer"}.get(action,"")
	var scales: Dictionary={}; var valid: bool=true
	for prop in ["axe","hammer","sickle"]:
		var bone: int=c.skeleton.find_bone("prop_"+prop)
		if bone<0: valid=false; continue
		var scale: Vector3=c.skeleton.get_bone_pose_scale(bone)
		var expected: float=1.0 if prop==active else .001
		valid=valid and scale.is_equal_approx(Vector3.ONE*expected)
		scales[prop]=[scale.x,scale.y,scale.z]
	return {"pass":valid,"active":active,"scales":scales}

func record(kind: String, tick: int, pos=Vector3.ZERO, action="idle") -> Dictionary:
	return {"id":1,"kind":kind,"category":"unit","owned":true,"remembered":false,"team":0,"last_seen_tick":tick,"pos":pos,"visual_action":action,"visual_moving":false,"visual_attack_tick":-1,"visual_hit_tick":-1}
func run() -> void:
	for kind in Controller.KINDS:
		var body:=Node3D.new(); root.add_child(body)
		var c=Controller.new()
		var bound: bool=c.bind(body,kind,Color("435d6c"))
		check(kind+" native rig exists",bound)
		if not bound: body.free(); continue
		check(kind+" has real skeleton",c.skeleton.get_bone_count()>=20 and c.skeleton.get_bone_count()<=32)
		check(kind+" manual clock",c.player.callback_mode_process==AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL and not c.player.is_playing())
		var clips: Dictionary={}
		for name in c.player.get_animation_list():
			if name=="RESET": continue
			var length: float=c.player.get_animation(name).length
			c._start(name,0,false,false); var start=pose(c)
			c.playhead=length*.35; c._apply_pose(.1); var middle=pose(c)
			c.playhead=length*.75; c._apply_pose(.1); var end=pose(c)
			check(kind+" "+name+" changes actual bones",start!=middle or middle!=end)
			check(kind+" "+name+" does not move body root",body.position==Vector3.ZERO and body.scale==Vector3.ONE)
			var legal=true
			var anim: Animation=c.player.get_animation(name)
			for track in anim.get_track_count():
				legal=legal and anim.track_get_type(track) in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D]
			check(kind+" "+name+" no gameplay/event tracks",legal)
			clips[name]=c.visual_evidence_snapshot()
			if kind=="villager":
				var tool_state: Dictionary=tools(c,name)
				check("villager "+name+" restores exact active and inactive tools",tool_state.pass,tool_state)
		if kind=="villager":
			var sequence: Array=["idle","gather_wood","idle","gather_food","build","repair","attack","carry_walk","walk","idle"]
			for index in sequence.size():
				var action: String=sequence[index]
				c._start(action,0,false,false); c._apply_pose(.1)
				var tool_state: Dictionary=tools(c,action)
				check("villager tool transition "+str(index)+" "+action,tool_state.pass,tool_state)
				tool_transitions.append({"index":index,"clip":action,"tools":tool_state})
			c.previous_tick=-1; c.running_last_frame=false
			c.observe(record(kind,0),.05,true)
			for index in 4:
				var action: String=["gather_wood","gather_food","build","repair"][index]
				var applied: Dictionary=record(kind,index+1,Vector3.ZERO,action)
				applied.visual_moving=true # Real build diagnostic leaves one queued point.
				var original: Dictionary=applied.duplicate(true)
				c.observe(applied,.05,true)
				check("villager applied "+action+" beats queued waypoint",c.clip==action and applied==original)
			var moving: Dictionary=record(kind,5,Vector3(.1,0,0))
			moving.visual_moving=true; c.observe(moving,.05,true)
			check("villager cleared work cue resumes actual walk",c.clip=="walk" and c.walk_rate>0)
		c.previous_tick=-1; c.running_last_frame=false
		c._start("idle",0,false,false);c.observe(record(kind,0),.05,true)
		var r=record(kind,1,Vector3(.10,0,0));r.visual_moving=true;c.observe(r,.05,true)
		for i in 5:
			r=record(kind,2+i,Vector3(.2+i*.1,0,0));r.visual_moving=true;c.observe(r,.05,true)
		check(kind+" displacement selects articulated walk",c.clip=="walk" and c.walk_rate>0 and c.playhead>0)
		var time: float=c.playhead
		r=record(kind,7,Vector3(.6,0,0));r.visual_moving=true;c.observe(r,.05,true)
		check(kind+" blocked movement stops cadence",c.walk_rate==0 and c.playhead==time)
		var before=pose(c);var applications:int=c.pose_applications
		c.observe(r,30,false);c.observe(r,30,true)
		check(kind+" pause/resume no backlog",pose(c)==before and c.pose_applications==applications)
		r=record(kind,8);r.visual_attack_tick=8;c.observe(r,.0,true)
		check(kind+" release seeks contact now",c.clip=="attack" and is_equal_approx(c.playhead,c.player.get_animation("attack").length*Controller.IMPACT_FRACTION[kind]))
		var released:float=c.playhead;c.observe(r,0,true)
		check(kind+" same release is not replayed",c.playhead==released)
		r=record(kind,9);r.visual_attack_tick=8;r.visual_hit_tick=9;c.observe(r,0,true)
		check(kind+" actual hit selects recoil",c.clip=="hit")
		c.start_death();check(kind+" death has separate lifecycle",c.dead and c.clip=="death" and not c.rig.get_meta("occlusion_authorized"))
		for i in 100:c.advance_death(.05,true)
		check(kind+" death completes bounded",c.finished)
		evidence[kind]=clips;c.release();body.free()
	var presenter=Presenter.new();var holder:=Node3D.new();root.add_child(holder)
	var r=record("villager",1);presenter.present(r,holder,Color("435d6c"),.05,true)
	check("live observed rig eligible for occlusion",presenter.occlusion_candidates().size()==1)
	holder.hide();check("hidden ancestor cannot leak evidence",presenter.visual_evidence_snapshot().live.is_empty() and presenter.occlusion_candidates().is_empty())
	holder.show();presenter.reconcile({})
	check("hidden enemy history/controller is destroyed",presenter.controllers.is_empty())
	presenter.clear();holder.free()
	var game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.test_mode=true
	game._update_visuals(.05)
	var snapshot=game._snapshot();var rng_state:int=game.rng.state
	for i in 10:game._update_visuals(.05)
	check("presentation cannot mutate game snapshot or RNG",game._snapshot()==snapshot and game.rng.state==rng_state)
	var unit=game._first(0,"villager")
	check("game has villager controller",game.character_presenter.controllers.has(unit.id))
	check("legacy whole-body bob removed",unit.body.position.y==0 and unit.body.rotation.z==0)
	var authority_count:int=game.entities.size();var radius:float=unit.radius
	game._kill(unit);game._publish_faction_views();game._update_visuals(.05)
	check("witnessed death creates visual without authority entity",game.entities.size()==authority_count and not unit.alive and unit.radius==radius and game.character_presenter.corpses.size()==1)
	check("dead controller no longer eligible",not game.character_presenter.controllers.has(unit.id))
	game._test_reset();check("restart clears action/death history",game.pending_visual_deaths.is_empty() and game.character_presenter.corpses.is_empty() and game.unit_action_cues==[{},{}])
	game.free()
	var failed=checks.filter(func(c):return not c.pass).size()
	var report={"checks":checks,"failed":failed,"pose_evidence":evidence,"tool_transitions":tool_transitions,"scope":"Native contracts only. No rendered motion, phone performance or user visual acceptance."}
	var file=FileAccess.open("res://reports/action-character-tests.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n");file.close()
	print("ACTION_CHARACTER_TESTS ",checks.size()," failed=",failed)
	quit(1 if failed else 0)
