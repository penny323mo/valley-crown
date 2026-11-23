extends SceneTree
## External diagnostic fixture, not a product scene or export resource.
const Rules=preload("res://scripts/rules.gd")
const DRAW_DEADLINE_MS=45000
var started_ms=0
var out=""
var dims=Vector2i.ZERO
var metadata_only=false
var game
var report={"checks":[],"frames":[],"scope":"Actual patched native scene on a fresh Age-I state. Camera manually centered on owned Town Center once; building selection, bookmark and return are ordinary viewport-routed synthetic touches. No browser, natural campaign or iPhone acceptance."}

func _initialize():
	started_ms=Time.get_ticks_msec()
	print("VC_CAPTURE_BOOT town_research_bookmarks")
	call_deferred("run")

func checkpoint(stage,details={}):
	var line=JSON.stringify({"stage":stage,"ms":Time.get_ticks_msec()-started_ms,"details":details})
	print("VC_CAPTURE_PROGRESS "+line)
	if out.is_empty() or not DirAccess.dir_exists_absolute(out):return
	var path=out+"/progress.jsonl"
	var f=FileAccess.open(path,FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f!=null:
		f.seek_end();f.store_line(line);f.flush();f.close()
	else:push_error("Cannot retain capture checkpoint "+stage)

func check(label,ok):
	report.checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
	return bool(ok)

func settle(n=5):
	for i in n:await process_frame

func finish():
	checkpoint("finish",{"states":report.frames.size()})
	report.failed=report.checks.filter(func(x):return not x.passed).size()
	report.png_count=report.frames.filter(func(x):return x.has("sha256")).size()
	report.result="FAIL" if report.failed else ("METADATA_ONLY" if metadata_only else "RENDERED")
	var f=FileAccess.open(out+"/report.json",FileAccess.WRITE)
	if f==null:push_error("Failed to write screenshot receipt");quit(2);return
	f.store_string(JSON.stringify(report,"  "));f.close()
	print(JSON.stringify({"checks":report.checks.size(),"failed":report.failed,"frames":report.frames.size(),"png_count":report.png_count,"result":report.result}))
	if is_instance_valid(game):game.free()
	quit(1 if report.failed else 0)

func tap(point,index):
	for pressed in [true,false]:
		var e=InputEventScreenTouch.new();e.position=point;e.index=index;e.pressed=pressed
		root.push_input(e);await process_frame
	await settle()

func shape(b):
	if not is_instance_valid(b):return []
	var r=b.get_global_rect()
	return [r.position.x,r.position.y,r.size.x,r.size.y]

func locate(kind,caption):
	for b in game.actions.get_children():
		if b is Button and b.get_meta("command_icon_kind","")==kind and b.text.begins_with(caption):return b
	return null

func reachable(button):
	if not is_instance_valid(button) or not button.is_visible_in_tree() or not game.action_scroll.is_ancestor_of(button):return false
	var v=Rect2(Vector2.ZERO,Vector2(dims))
	var r=button.get_global_rect()
	return r.size.x>=44 and r.size.y>=44 and v.encloses(r) and game.action_scroll.get_global_rect().encloses(r)

func capture(name,controls,focus_id,bank,transform,zoom,visible_center):
	checkpoint("state_ready",{"state":name,"scroll":game.action_scroll.scroll_horizontal})
	if not check(name+" all required controls fully reachable",controls.values().all(reachable)):return false
	var state={"name":name,"focus_id":focus_id,"camera_focus":str(game.camera_focus),"camera_transform":str(transform),"zoom":zoom,
		"centered_town_center":[visible_center.x,visible_center.y],"same_camera":game.camera.global_transform==transform and game.camera_zoom==zoom,
		"native_scroll":game.action_scroll.scroll_horizontal,"bank_milli":bank.duplicate(true),"labels":{},"rects":{}}
	for key in controls:
		state.labels[key]=controls[key].text
		state.rects[key]=shape(controls[key])
	if not check(name+" kept same camera and no pending input transaction",state.same_camera and game.selected==[focus_id] and game.all_touch_ids.is_empty() and game.commands.is_empty() and game.economy.bank_milli(0)==bank):return false
	if not metadata_only:
		var draws=[0]
		var witness=func():draws[0]+=1
		RenderingServer.frame_post_draw.connect(witness)
		var start=Time.get_ticks_msec()
		checkpoint("draw_begin",{"state":name,"deadline_ms":DRAW_DEADLINE_MS,"draws_needed":2})
		RenderingServer.render_loop_enabled=true
		while draws[0]<2 and Time.get_ticks_msec()-start<DRAW_DEADLINE_MS:await process_frame
		RenderingServer.render_loop_enabled=false
		RenderingServer.frame_post_draw.disconnect(witness)
		checkpoint("draw_end",{"state":name,"draws":draws[0],"draw_ms":Time.get_ticks_msec()-start})
		if not check(name+" actual Compatibility viewport completed two draws",draws[0]>=2):return false
		checkpoint("readback_begin",{"state":name})
		var img=root.get_texture().get_image()
		checkpoint("readback_end",{"state":name,"width":img.get_width() if img!=null else -1,"height":img.get_height() if img!=null else -1})
		if not check(name+" unedited game PNG has exact dimensions",img!=null and not img.is_empty() and img.get_size()==dims):return false
		var palette={}
		for y in range(0,dims.y,17):
			for x in range(0,dims.x,17):palette[img.get_pixel(x,y).to_rgba32()]=true
		if not check(name+" nonblank real image",palette.size()>24):return false
		state.file=name+".png"
		var path=out+"/"+state.file
		if not check(name+" PNG accepted",img.save_png(path)==OK):return false
		state.sha256=FileAccess.get_sha256(path)
		checkpoint("png_saved",{"state":name,"sha256":state.sha256})
	report.frames.append(state)
	return true

func run():
	RenderingServer.render_loop_enabled=false
	var args=OS.get_cmdline_user_args()
	if args.size() not in [6,7] or (args.size()==7 and args[6]!="--metadata-only"):
		push_error("Usage: -- OUT WIDTH HEIGHT BUILD GAME_GD_SHA RULES_GD_SHA [--metadata-only]");quit(2);return
	out=args[0];dims=Vector2i(int(args[1]),int(args[2]));metadata_only=args.size()==7
	if dims not in [Vector2i(568,320),Vector2i(390,844)] or not out.begins_with("/") or DirAccess.dir_exists_absolute(out) or FileAccess.file_exists(out):
		push_error("Expected a new absolute directory, then 568x320 or 390x844");quit(2);return
	if DirAccess.make_dir_recursive_absolute(out)!=OK:push_error("Cannot create fixture output");quit(2);return
	report.size=[dims.x,dims.y]
	report.build=Rules.BUILD_ID
	report.engine=Engine.get_version_info()
	report.display=DisplayServer.get_name()
	report.renderer=RenderingServer.get_current_rendering_method()
	report.video_adapter=RenderingServer.get_video_adapter_name()
	report.fixture_sha256=FileAccess.get_sha256(get_script().resource_path)
	report.game_sha256=FileAccess.get_sha256("res://scripts/game.gd")
	report.rules_sha256=FileAccess.get_sha256("res://scripts/rules.gd")
	report.metadata_only=metadata_only
	checkpoint("initialize",{"display":report.display,"build":report.build})
	if not check("expected build and reviewed input files",report.build==args[3] and report.game_sha256==args[4] and report.rules_sha256==args[5]):
		finish();return
	if not check("rendered captures require actual display",metadata_only or report.display!="headless"):
		finish();return
	root.size=dims;await settle()
	if not check("actual requested native viewport",root.size==dims):finish();return
	checkpoint("load_scene_begin")
	game=load("res://main.tscn").instantiate()
	game.skirmish_mode="practice"
	root.add_child(game);game.set_process(false)
	checkpoint("load_scene_end")
	game.test_mode=true;game.ai_enabled=false
	game._test_reset();game.set_process(false);game._layout_ui();await settle()
	var keep=game._first(0,"town_center")
	if not check("actual owned Town Center available in fresh Age I",not keep.is_empty() and not game._age2(0)):finish();return
	game.camera_focus=keep.pos;game.camera_zoom=22.0
	game._camera_update();game._update_visuals(0);game._refresh_fog();await settle()
	var center=game.camera.unproject_position(keep.pos)
	var target=game.camera.unproject_position(keep.pos+Vector3.UP)
	var middle=Vector2(dims)*0.5
	if not check("Town Center is centered and actually selectable behind no interface",
		game.camera_focus==keep.pos and center.distance_to(middle)<=2.0 and game._box_point_in_world(target) and game._pick(target)==keep.id):
		report.center_problem={"ground":str(center),"target":str(target),"center":str(middle),"picked":game._pick(target)}
		finish();return
	checkpoint("town_world_selection",{"id":keep.id,"x":target.x,"y":target.y})
	await tap(target,30)
	var cam=game.camera.global_transform
	var bank=game.economy.bank_milli(0).duplicate(true)
	var zoom=game.camera_zoom
	var villager=locate("villager","訓練")
	var scout=locate("scout","訓練")
	var join=game.town_research_jump
	var research=locate("age2","城防時代")
	if not check("ordinary world tap selected the keep and both Train cards and Research are initially visible",
		game.selected==[keep.id] and reachable(villager) and reachable(scout) and reachable(join) and join.text=="研究 ›" and not reachable(research) and game.action_scroll.scroll_horizontal==0 and game.commands.is_empty()):
		finish();return
	if not await capture("01-training-before-jump",{"train_villager":villager,"train_scout":scout,"research_jump":join},keep.id,bank,cam,zoom,center):
		finish();return
	await tap(join.get_global_rect().get_center(),31)
	var back=game.town_research_return
	if not check("one ordinary tap makes real research row and back button reachable at same camera",
		reachable(research) and reachable(back) and back.text=="‹ 訓練" and root.gui_get_focus_owner()==back and game.action_scroll.scroll_horizontal>0 and game.camera.global_transform==cam):
		finish();return
	if not await capture("02-research-after-jump",{"age_research":research,"return_to_training":back},keep.id,bank,cam,zoom,center):
		finish();return
	await tap(back.get_global_rect().get_center(),31)
	var returned=reachable(villager) and reachable(scout) and reachable(join) and root.gui_get_focus_owner()==join and game.action_scroll.scroll_horizontal==0
	check("actual return again fully exposes both 44px train cards and the bookmark",returned)
	check("entire round trip left world, queue, selection, bank and camera unchanged",game.commands.is_empty() and keep.queue.is_empty() and game.economy.bank_milli(0)==bank and game.selected==[keep.id] and game.camera.global_transform==cam and game.camera_zoom==zoom and game.all_touch_ids.is_empty())
	report.returned={"verified":returned,"train_villager":shape(villager),"train_scout":shape(scout),"research_jump":shape(join)}
	check("exactly two meaningful game states",report.frames.size()==2)
	finish()
