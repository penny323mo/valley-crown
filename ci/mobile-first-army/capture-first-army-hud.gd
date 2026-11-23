extends SceneTree
## Test only: actual native main.tscn with one fixed reproducible world plot.
const Rules=preload("res://scripts/rules.gd")
const SIZE=Vector2i(568,320)
const PLOT=Vector3(-20.5,0,14.5)
var out=""
var baseline=false
var metadata_only=false
var boot=0
var game
var checks=[]
var states=[]
var info={}

func _initialize():
	boot=Time.get_ticks_msec()
	print("VC_CAPTURE_BOOT first_army_hud")
	call_deferred("run")
func checkpoint(stage,details={}):
	var line=JSON.stringify({"stage":stage,"ms":Time.get_ticks_msec()-boot,"details":details})
	print("VC_CAPTURE_PROGRESS "+line)
	if out.is_empty() or not DirAccess.dir_exists_absolute(out):return
	var path=out+"/progress.jsonl"
	var f=FileAccess.open(path,FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f!=null:f.seek_end();f.store_line(line);f.flush();f.close()
func ck(name,value):
	checks.append({"name":name,"passed":bool(value)})
	if not value:push_error(name)
	return bool(value)
func frames(n=5):
	for i in n:await process_frame
func settle():
	game._process(0);game._update_hud();game._layout_ui()
	await frames()
func finish():
	var failed=checks.filter(func(c):return not c.passed).size()
	info.checks=checks;info.failed=failed;info.frames=states
	info.result="FAIL" if failed else ("METADATA_ONLY" if metadata_only else "RENDERED")
	info.png_count=states.filter(func(s):return s.has("sha256")).size()
	checkpoint("finish",{"states":states.size(),"failed":failed,"png_count":info.png_count})
	var f=FileAccess.open(out+"/report.json",FileAccess.WRITE)
	if f==null:quit(2);return
	f.store_string(JSON.stringify(info,"  "));f.close()
	if is_instance_valid(game):game.free()
	quit(1 if failed else 0)
func touch(point,down,index=0):
	var e=InputEventScreenTouch.new();e.index=index;e.position=point;e.pressed=down
	root.push_input(e);await process_frame
func tap(point):
	await touch(point,true);await touch(point,false);await settle()
func swipe(a,b):
	await touch(a,true)
	var e=InputEventScreenDrag.new();e.index=0;e.position=b;e.relative=b-a;root.push_input(e)
	await process_frame
	await touch(b,false);await settle()
func rect(r):
	return [r.position.x,r.position.y,r.size.x,r.size.y]
func fits(b,lane):
	if not is_instance_valid(b) or not b.is_visible_in_tree():return false
	var r=b.get_global_rect()
	return r.size.x>=44 and r.size.y>=44 and root.get_visible_rect().encloses(r) and lane.get_global_rect().encloses(r)
func central_band():
	var best=0;var n=0
	for y in SIZE.y:
		if game._box_point_in_world(Vector2(SIZE.x*.5,y)):
			n+=1;best=maxi(best,n)
		else:n=0
	return best
func own_commands():return game.commands.filter(func(c):return c.team==0)

func real_frame(name,fields):
	var state=fields.duplicate(true);state.name=name
	checkpoint("state_ready",{"state":name,"band":fields.get("world_rows",-1)})
	if not metadata_only:
		var draws=[0]
		var observer=func():draws[0]+=1
		RenderingServer.frame_post_draw.connect(observer)
		var start=Time.get_ticks_msec()
		checkpoint("draw_begin",{"state":name,"needed":2,"deadline_ms":45000})
		RenderingServer.render_loop_enabled=true
		while draws[0]<2 and Time.get_ticks_msec()-start<45000:await process_frame
		RenderingServer.render_loop_enabled=false
		RenderingServer.frame_post_draw.disconnect(observer)
		checkpoint("draw_end",{"state":name,"draws":draws[0],"ms":Time.get_ticks_msec()-start})
		if not ck(name+" two actual GPU frame completions",draws[0]>=2):return false
		checkpoint("readback_begin",{"state":name})
		var img=root.get_texture().get_image()
		checkpoint("readback_end",{"state":name,"valid":img!=null})
		if not ck(name+" actual native image dimensions",img!=null and not img.is_empty() and img.get_size()==SIZE):return false
		var palette={}
		for y in range(0,SIZE.y,13):
			for x in range(0,SIZE.x,13):palette[img.get_pixel(x,y).to_rgba32()]=true
		if not ck(name+" real native unmodified view is nonblank",palette.size()>24):return false
		state.file=name+".png"
		var path=out+"/"+state.file
		if not ck(name+" native PNG saved",img.save_png(path)==OK):return false
		state.sha256=FileAccess.get_sha256(path)
		checkpoint("png_saved",{"state":name,"sha256":state.sha256})
	states.append(state)
	return true
func run():
	RenderingServer.render_loop_enabled=false
	var args=OS.get_cmdline_user_args()
	if args.size() not in [5,6] or args[1] not in ["baseline","candidate"] or (args.size()==6 and args[5]!="--metadata-only"):
		push_error("Expected -- OUT VIEW BUILD GAME_SHA RULES_SHA [--metadata-only]");quit(2);return
	out=args[0];baseline=args[1]=="baseline";metadata_only=args.size()==6
	if not out.begins_with("/") or DirAccess.dir_exists_absolute(out) or FileAccess.file_exists(out) or DirAccess.make_dir_recursive_absolute(out)!=OK:quit(2);return
	info={"scope":"Actual native matched Range preview at the same camera, terrain, owned starting worker, legal plot and bank. Genuine viewport-routed synthetic touch. Candidate additional normal paid Range completion. No browser or iPhone acceptance.","build":Rules.BUILD_ID,"role":args[1],"size":[SIZE.x,SIZE.y],"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"video_adapter":RenderingServer.get_video_adapter_name(),"game_sha":FileAccess.get_sha256("res://scripts/game.gd"),"rules_sha":FileAccess.get_sha256("res://scripts/rules.gd"),"metadata_only":metadata_only}
	checkpoint("initialize",{"build":info.build,"display":info.display})
	if not ck("exact selected scene source bytes",info.build==args[2] and info.game_sha==args[3] and info.rules_sha==args[4] and (metadata_only or info.display!="headless")):finish();return
	root.size=SIZE;await frames()
	if not ck("actual viewport 568×320",root.size==SIZE):finish();return
	checkpoint("load_scene_begin")
	game=load("res://main.tscn").instantiate()
	game.skirmish_mode="practice";root.add_child(game);game.set_process(false)
	game.camera_zoom=22 # The actual menu shell's fresh short-landscape zoom.
	await settle()
	checkpoint("load_scene_end")
	var worker=game._get_entity(4)
	var anchor=game.camera.unproject_position(worker.pos+Vector3(0,.6,0))
	if not ck("exact real opening worker is directly tappable",worker.alive and worker.team==0 and worker.kind=="villager" and game._box_point_in_world(anchor) and game._friendly_unit_pick(anchor,game._pick(anchor))==worker.id):finish();return
	await tap(anchor)
	if not ck("ordinary world input selected matched worker",game.selected==[4] and own_commands().is_empty()):finish();return
	var range_card
	for b in game.actions.get_children():
		if b is Button and b.get_meta("command_icon_kind","")=="range":range_card=b;break
	if not ck("Range has genuine build control",is_instance_valid(range_card)):finish();return
	var bank=game.economy.bank_milli(0).duplicate(true);var cam=game.camera.global_transform
	var lane=game.action_scroll.get_global_rect()
	if not fits(range_card,game.action_scroll):await swipe(lane.get_center()+Vector2(58,0),lane.get_center()-Vector2(58,0))
	if not ck("real strip swipe safely reveals costed Range action",fits(range_card,game.action_scroll) and own_commands().is_empty() and game.economy.bank_milli(0)==bank):finish();return
	await tap(range_card.get_global_rect().get_center())
	var p=game.camera.unproject_position(PLOT)
	if not ck("both views use exact same safe legal projected placement point",game.build_mode=="range" and game._box_point_in_world(p) and game._placement_reason("range",PLOT,0,worker.id).is_empty()):finish();return
	await tap(p)
	var band=central_band()
	var q=game.queue_label
	var price_width=q.get_theme_font("font").get_string_size(q.text,HORIZONTAL_ALIGNMENT_LEFT,-1,q.get_theme_font_size("font_size")).x
	if not ck("both genuinely aimed and still unpaid with same actor, camera and no order",game.build_preview_held and game.pointer_world==PLOT and game._build_preview_reason().is_empty() and not game.build_confirm.disabled and fits(game.build_confirm,game.action_scroll) and game.selected==[4] and game.camera.global_transform==cam and own_commands().is_empty() and game.economy.bank_milli(0)==bank):finish();return
	if not ck("observed old six rows versus corrected at least 64 and whole price",band==6 and q.size.x<price_width if baseline else band>=64 and q.size.x>=price_width):finish();return
	var plot_state={"build_mode":game.build_mode,"plot":[PLOT.x,PLOT.y,PLOT.z],"plot_screen":[p.x,p.y],"layout":game.layout_id,"camera":str(cam),"zoom":game.camera_zoom,"bank_milli":bank,"selected":game.selected.duplicate(),"tick":game.tick_count,"price":q.text,"price_rect":rect(q.get_global_rect()),"price_measured_width":price_width,"hud_bottom":rect(game.hud_bottom.get_global_rect()),"world_rows":band,"unpaid":true,"confirm_armed":true}
	if not await real_frame("range-placement",plot_state):finish();return
	if baseline:
		finish();return

	await tap(game.build_confirm.get_global_rect().get_center())
	if not ck("only ordinary Confirm submits exactly one real Range order",own_commands().size()==1 and own_commands()[0].type=="build" and own_commands()[0].kind=="range"):finish();return
	game._process(Rules.TICK)
	var site=game._first(0,"range")
	if not ck("actual authority debits exactly120 wood and creates paid site",not site.is_empty() and not site.built and game.economy.bank_milli(0).wood==bank.wood-120000):finish();return
	checkpoint("normal_paid_construction_begin")
	for i in 1300:
		if site.built:break
		game._process(Rules.TICK)
	await settle()
	var projected=game.camera.unproject_position(site.pos+Vector3.UP)
	var toast=game.tutorial_panel.get_global_rect()
	if not ck("actual paid completion relocates notification away from exact building",site.built and toast.size.x<284 and not toast.has_point(projected) and game._box_point_in_world(projected) and game.camera.global_transform==cam and game.selected==[4] and game.toast_label.visible):finish();return
	if not await real_frame("paid-range-completion",{"build_mode":game.build_mode,"plot":[PLOT.x,PLOT.y,PLOT.z],"building_screen":[projected.x,projected.y],"layout":game.layout_id,"camera":str(cam),"zoom":game.camera_zoom,"bank_milli":game.economy.bank_milli(0),"selected":game.selected.duplicate(),"tick":game.tick_count,"completion_toast":game.toast_label.text,"notice_rect":rect(toast),"paid":true,"building_id":site.id}):finish();return
	var seq=game.command_sequence
	await tap(projected)
	ck("one ordinary tap on exposed center selects paid Range without adding order",game.selected==[site.id] and game.command_sequence==seq and own_commands().is_empty())
	finish()
