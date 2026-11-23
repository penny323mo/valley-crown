extends SceneTree
## External capture fixture; never part of a product export.
const Rules=preload("res://scripts/rules.gd")
const Icons=preload("res://scripts/command_icons.gd")
var game
var out=""
var metadata_only=false
var dims=Vector2i.ZERO
var report={"checks":[],"frames":[],"scope":"Actual patched game scene and ordinary viewport-routed native input. Funded fixture; age-II eligibility is seeded for the supply scene. Native rendered UI only; not browser, physical phone, or natural campaign."}

func _initialize():call_deferred("run")

func check(label,ok):
	report.checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
	return bool(ok)

func settle(count=5):
	for i in count:await process_frame

func finish():
	report.failed=report.checks.filter(func(x):return not x.passed).size()
	report.png_count=report.frames.filter(func(x):return x.has("sha256")).size()
	report.result="FAIL" if report.failed else ("METADATA_ONLY" if metadata_only else "RENDERED")
	var file=FileAccess.open(out+"/report.json",FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(report,"  "));file.close()
	else:
		push_error("Capture report could not be written")
		quit(2)
		return
	print(JSON.stringify({"checks":report.checks.size(),"failed":report.failed,"frames":report.frames.size(),"png_count":report.png_count,"result":report.result}))
	if is_instance_valid(game):game.free()
	quit(1 if report.failed else 0)

func in_strip(button):
	return is_instance_valid(button) and button.is_visible_in_tree() and button.size.y>=44 and game.action_scroll.get_global_rect().encloses(button.get_global_rect())

func show_action(button):
	if not is_instance_valid(button):return false
	game.action_scroll.ensure_control_visible(button)
	await settle()
	return in_strip(button)

func action_icon(kind,prefix):
	for b in game.actions.get_children():
		if b is Button and b.get_meta("command_icon_kind","")==kind and b.text.begins_with(prefix):return b
	return null

func tap(point,index):
	for down in [true,false]:
		var e=InputEventScreenTouch.new();e.index=index;e.position=point;e.pressed=down
		root.push_input(e);await process_frame
	await settle()

func tap_icon(button,index):
	await tap(button.get_global_rect().position+Vector2(18,button.size.y*0.5),index)

func refresh_and_select(ids):
	game._publish_faction_views()
	game._select(ids);game._update_hud();game._layout_ui()
	await settle()

func focus(position):
	game.camera_focus=position
	game._camera_update();game._update_visuals(0);game._refresh_fog()
	await settle()

func capture(name,button,details={}):
	if not check(name+": actual action fully visible",in_strip(button) and button.icon!=null):return false
	var r=button.get_global_rect()
	var frame=details.duplicate(true)
	frame.merge({"name":name,"button_text":button.text,"button_icon":button.icon.resource_path,"button_disabled":button.disabled,
		"button_rect":[r.position.x,r.position.y,r.size.x,r.size.y],"tick":game.tick_count,
		"selected":game.selected.duplicate(),"bank_milli":game.economy.bank_milli(0).duplicate(true)})
	if not metadata_only:
		await settle(8)
		await RenderingServer.frame_post_draw
		var img=root.get_texture().get_image()
		if not check(name+": rendered viewport matches requested size",img!=null and not img.is_empty() and img.get_size()==dims):return false
		var palette={}
		for y in range(0,dims.y,17):
			for x in range(0,dims.x,17):palette[img.get_pixel(x,y).to_rgba32()]=true
		if not check(name+": nonblank viewport",palette.size()>24):return false
		var path=out+"/"+name+".png"
		if not check(name+": unedited PNG saved",img.save_png(path)==OK):return false
		frame.file=name+".png";frame.sha256=FileAccess.get_sha256(path)
	report.frames.append(frame)
	return true

func choose_house_site():
	# A fixture search picks only screen points, not private game commands.
	# Keep the actual regular tap and full preview validation in the loop.
	var candidates=[game.camera.unproject_position(game.pointer_world)]
	for y in range(maxi(80,int(dims.y*0.26)),int(dims.y*0.75),15):
		for x in range(maxi(40,int(dims.x*0.15)),int(dims.x*0.85),18):
			candidates.append(Vector2(x,y))
	for p in candidates:
		if not game._box_point_in_world(p):continue
		await tap(p,61)
		game._update_ghost();await settle()
		if game.placement_ok and game.build_preview_held:return true
	return false

func run():
	var args=OS.get_cmdline_user_args()
	if args.size() not in [6,7] or (args.size()==7 and args[6]!="--metadata-only"):
		push_error("Usage: -- OUTPUT WIDTH HEIGHT BUILD GAME_SCRIPT_SHA256 COMMAND_ICONS_SHA256 [--metadata-only]")
		quit(2);return
	out=args[0];dims=Vector2i(int(args[1]),int(args[2]));metadata_only=args.size()==7
	if dims not in [Vector2i(390,844),Vector2i(844,390)] or not out.begins_with("/") or DirAccess.dir_exists_absolute(out) or FileAccess.file_exists(out):
		push_error("Expected a new absolute directory and supported portrait or landscape size")
		quit(2);return
	if DirAccess.make_dir_recursive_absolute(out)!=OK:
		push_error("Cannot create capture output");quit(2);return
	report.metadata_only=metadata_only
	report.size=[dims.x,dims.y]
	report.build=Rules.BUILD_ID
	report.engine=Engine.get_version_info()
	report.display=DisplayServer.get_name()
	report.renderer=RenderingServer.get_current_rendering_method()
	report.fixture_sha256=FileAccess.get_sha256(get_script().resource_path)
	report.game_sha256=FileAccess.get_sha256("res://scripts/game.gd")
	report.command_icons_sha256=FileAccess.get_sha256("res://scripts/command_icons.gd")
	for kind in Icons.UPGRADE_ICONS:
		var t=Icons.UPGRADE_ICONS[kind]
		if not report.has("symbols"):report.symbols={}
		report.symbols[kind]=FileAccess.get_sha256(t.resource_path)
	if not check("requested build and exact two changed scripts",report.build==args[3] and report.game_sha256==args[4] and report.command_icons_sha256==args[5]):
		finish();return
	if not check("real display required for native PNG output",metadata_only or report.display!="headless"):
		finish();return
	root.size=dims;await settle()
	if not check("requested native viewport",root.size==dims):finish();return
	game=load("res://main.tscn").instantiate()
	game.skirmish_mode="practice";root.add_child(game);game.set_process(false)
	game.test_mode=true;game.ai_enabled=false
	var stock={"food":3000,"wood":3000,"stone":3000,"iron":3000}
	game._test_reset([stock,stock.duplicate(true)]);game.set_process(false)
	await settle()
	var keep=game._first(0,"town_center")
	var worker=game._first(0,"villager")

	await focus(worker.pos)
	await refresh_and_select([worker.id])
	var house=action_icon("house","民居")
	var house_reached=await show_action(house)
	if not check("ordinary house choice reachable",house_reached):
		finish();return
	await tap_icon(house,60)
	if not check("ordinary house preview started without payment",game.build_mode=="house" and game.commands.is_empty()):
		finish();return
	var legal=await choose_house_site()
	var confirm=game.build_confirm
	var confirm_reached=await show_action(confirm)
	if not check("ordinary tap enables real house confirm with model portrait",legal and confirm_reached and not confirm.disabled and confirm.text=="確認建造" and confirm.icon==Icons.ICONS.house and game.commands.is_empty()):
		finish();return
	if not await capture("01-house-confirm",confirm,{"build_mode":game.build_mode,"preview_held":game.build_preview_held,"placement_ok":game.placement_ok}):
		finish();return

	game._cancel_mode();await focus(keep.pos)
	await refresh_and_select([keep.id])
	var research=action_icon("age2","城防時代")
	var age_reached=await show_action(research)
	if not check("ordinary age-II research action reachable and not disabled",age_reached and not research.disabled):
		finish();return
	var bank=game.economy.bank_milli(0).duplicate(true)
	await tap_icon(research,62)
	if not check("ordinary touch submitted exact age research",game.commands.size()==1 and game.commands[0].type=="research" and game.commands[0].building==keep.id):
		finish();return
	game._tick(Rules.TICK);await refresh_and_select([keep.id])
	var paid=game.economy.bank_milli(0)
	if not check("age-II research really paid and queued",keep.queue.size()==1 and keep.queue[0].kind=="age2" and bank.food-paid.food==350000 and bank.wood-paid.wood==150000 and bank.iron-paid.iron==50000):
		finish();return
	var age_item=keep.queue[0]
	var age_cancel=game.actions.get_node_or_null("CancelQueue%d" % age_item.queue_id)
	var age_cancel_reached=await show_action(age_cancel)
	if not check("age queue shows actual refund and matching symbol",age_cancel_reached and age_cancel.icon==Icons.UPGRADE_ICONS.age2 and age_cancel.text.begins_with("取消城防時代") and age_cancel.text.contains("退回")):
		finish();return
	if not await capture("02-paid-age-queue",age_cancel,{"queue_id":age_item.queue_id,"receipt_id":age_item.receipt_id,"kind":age_item.kind}):
		finish();return

	# Further stage is an explicitly seeded Age II test location, not a claim
	# that the full 90-second research and a storehouse build were played.
	game.age_completed_tick[0]=game.tick_count-1;report.supply_fixture="Age II flag and owned completed storehouse seeded; payment and queue are not seeded"
	var stockpile=game._spawn("storehouse",0,Vector3(-21,0,14))
	game._navigation_rebuild();game._update_vision();await focus(stockpile.pos)
	await refresh_and_select([stockpile.id])
	var supply=game.actions.get_node_or_null("SupplyStationUpgrade")
	var supply_reached=await show_action(supply)
	if not check("frontline supply action reachable and not disabled",supply_reached and not supply.disabled and supply.icon==Icons.UPGRADE_ICONS.supply_station):
		finish();return
	bank=game.economy.bank_milli(0).duplicate(true)
	await tap_icon(supply,63)
	if not check("ordinary touch submitted exact supply upgrade",game.commands.size()==1 and game.commands[0].type=="supply_upgrade" and game.commands[0].building==stockpile.id):
		finish();return
	game._tick(Rules.TICK);await refresh_and_select([stockpile.id])
	paid=game.economy.bank_milli(0)
	if not check("frontline supply really paid and queued",stockpile.queue.size()==1 and stockpile.queue[0].kind=="supply_station" and bank.food-paid.food==100000 and bank.wood-paid.wood==100000):
		finish();return
	var item=stockpile.queue[0]
	var cancel=game.actions.get_node_or_null("CancelQueue%d" % item.queue_id)
	var cancel_reached=await show_action(cancel)
	if not check("frontline queue shows actual refund and matching symbol",cancel_reached and cancel.icon==Icons.UPGRADE_ICONS.supply_station and cancel.text.begins_with("取消前線補給站") and cancel.text.contains("退回")):
		finish();return
	if not await capture("03-paid-supply-queue",cancel,{"queue_id":item.queue_id,"receipt_id":item.receipt_id,"kind":item.kind}):
		finish();return
	check("all three expected capture states observed",report.frames.size()==3)
	finish()
