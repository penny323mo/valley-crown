extends SceneTree
# External hosted-only native integration. No render or physical-phone acceptance.
const EXPECTED_BUILD = "vc-f605f947768e"
const GAME_SHA = "ed7bcf5e086871712f33ec1b88cc0f172b9f2ab0b5d53945c841a98a14967db6"
var game
var rows: Array = []
var report_path = ""
func _initialize(): call_deferred("run")
func check(name: String, passed: bool):
	rows.append({"name":name,"pass":passed})
	print("SELECTION_CHECK ",name," ",passed)
func settle():
	await process_frame
	await process_frame
func workers():
	var ids: Array = []
	for ent in game.faction_views[0].records().values():
		if ent.alive and ent.team==0 and ent.kind=="villager": ids.append(ent.id)
	return ids
func target_ids(kind: String):
	if kind=="home": return [game._first(0,"town_center").id]
	if kind=="different": return [workers()[1]]
	var ids: Array = []
	for ent in game.faction_views[0].records().values():
		if not ent.alive or ent.team!=0 or ent.category!="unit": continue
		if (kind=="army" and ent.kind!="villager") or (kind=="scout" and ent.kind=="scout") or (kind=="same" and ent.kind=="villager"): ids.append(ent.id)
	return ids
func same_ids(a: Array,b: Array):
	var aa=a.duplicate(); var bb=b.duplicate(); aa.sort(); bb.sort(); return aa==bb
func reset():
	game._cancel_mode(); game._test_reset(); game.compact_menu.hide(); game.compact_menu_dismiss.hide()
	game.camera_focus=game.MapRoutes.home(0); game._camera_update(); game._publish_faction_views(); game._update_hud()
func begin_preview(ids: Array,held: bool):
	game._select(ids); game._start_build("house")
	# Use the actual guided public plot and normal tap handler, not a forced legal result.
	var legal=game._placement_reason("house",game.pointer_world,0,game._selected_builder()).is_empty()
	if held: game._tap(game.camera.unproject_position(game.pointer_world),true)
	return legal and game.build_mode=="house" and game.build_preview_held==held and is_instance_valid(game.ghost)
func select_target(kind: String,ids: Array):
	if kind=="home": game._compact_menu_action(game._home)
	elif kind=="different": game._compact_menu_action(func(): game._select(ids))
	elif kind=="same": game._compact_menu_action(func(): game._select_group("villagers"))
	elif kind=="empty": game._compact_menu_action(func(): game._select_group("idle"))
	else: game._compact_menu_action(func(): game._select_group(kind))
func selection_case(kind: String,held: bool):
	reset(); await settle()
	if kind=="empty":
		# Controlled setup makes the real Idle Villagers menu target empty.
		for id in workers(): game._get_entity(id).state="move"
		game._publish_faction_views()
	var prefix=kind+":"+("held" if held else "unheld")+":"
	var initial=workers() if kind=="same" else [workers()[0]]
	var expected=target_ids(kind)
	check(prefix+"preview_setup",begin_preview(initial,held))
	var old_ghost=game.ghost
	game._toggle_compact_menu()
	check(prefix+"menu_preserves_preview",game.compact_menu.visible and game.build_mode=="house" and game.build_preview_held==held and game.ghost==old_ghost)
	var bank=game.economy.bank_milli(0).duplicate(true)
	var command_count=game.commands.size(); var entity_count=game.entities.size()
	# Controlled in-flight world pointer; selection must quarantine its late continuation.
	var press=InputEventScreenTouch.new(); press.index=37; press.position=Vector2(195,300); press.pressed=true
	game._track_pointer_input(press,root); game._unhandled_input(press)
	select_target(kind,expected)
	check(prefix+"selection_and_menu",same_ids(game.selected,expected) and not game.compact_menu.visible and not game.compact_menu_dismiss.visible)
	check(prefix+"mode_cleared",game.build_mode.is_empty() and not game.build_preview_held and not game.touch_command and not game.box_select_mode)
	var quarantined=game.canceled_touch_ids.has(37) and game.touch_press_epochs.is_empty() and game.gui_touch_press.is_empty() and game.all_touch_ids.is_empty() and game.touch_points.is_empty()
	var drag=InputEventScreenDrag.new(); drag.index=37; drag.position=Vector2(200,305); drag.relative=Vector2(5,5)
	game._track_pointer_input(drag,root)
	var release=InputEventScreenTouch.new(); release.index=37; release.position=drag.position; release.pressed=false
	game._track_pointer_input(release,root)
	check(prefix+"pointer_quarantined",quarantined and not game.canceled_touch_ids.has(37) and game.touch_points.is_empty() and game.all_touch_ids.is_empty() and same_ids(game.selected,expected))
	await settle()
	check(prefix+"ghost_retired",game.ghost==null and not is_instance_valid(old_ghost))
	check(prefix+"normal_actions",game.build_confirm==null and game.actions.get_child_count()>0 and not game.selection_title.text.begins_with("建造 "))
	check(prefix+"no_economic_or_authority_changes",game.economy.bank_milli(0)==bank and game.commands.size()==command_count and game.entities.size()==entity_count)
func negative_controls():
	reset(); await settle()
	var builder=workers()[0]
	var prepared=begin_preview([builder],true)
	var old_ghost=game.ghost; var old_plot=game.pointer_world
	game._toggle_compact_menu(); game._toggle_compact_menu(); game._toggle_compact_menu()
	check("negative:menu_close_reopen_preserves_preview",prepared and game.compact_menu.visible and game.build_mode=="house" and game.build_preview_held and game.ghost==old_ghost and game.pointer_world==old_plot)
	game._cancel_mode(); game.compact_menu.hide(); game.compact_menu_dismiss.hide()
	var press=InputEventScreenTouch.new(); press.index=38; press.position=Vector2(195,300); press.pressed=true
	game._track_pointer_input(press,root); game._unhandled_input(press)
	var epoch=game.touch_press_epochs.get(38,-1)
	game._select_group("scout")
	check("negative:ordinary_selection_preserves_pointer",game.build_mode.is_empty() and not game.canceled_touch_ids.has(38) and 38 in game.all_touch_ids and game.touch_points.has(38) and epoch>=0 and game.touch_press_epochs.get(38,-1)==epoch)
func confirm_and_paid_site():
	reset(); await settle()
	var builder=workers()[0]
	check("confirm:preview_setup",begin_preview([builder],true))
	var plot=game.pointer_world
	var before=game.economy.bank_milli(0).duplicate(true)
	game._confirm_build()
	var valid=game.commands.size()==1
	if valid:
		var command=game.commands[0]
		valid=command.type=="build" and command.builder==builder and command.kind=="house" and command.position==plot
	check("confirm:original_builder_queued",valid)
	check("confirm:preview_cleared",game.build_mode.is_empty() and not game.build_preview_held and game.ghost==null and game.selected==[builder])
	if valid:
		var command=game.commands.pop_front(); game._execute(command)
	var site=game._first(0,"house")
	var bank=game.economy.bank_milli(0).duplicate(true)
	var paid=not site.is_empty() and not site.get("cost_receipt_id","").is_empty() and bank.wood==before.wood-int(game.COSTS.house.wood)*1000 and bank.food==before.food
	check("confirm:authority_paid_site",paid and game._get_entity(builder).target==site.get("id",-1))
	var saved={}
	if not site.is_empty():
		for field in ["id","alive","built","progress","cost_receipt_id"]: saved[field]=site[field]
	game._publish_faction_views()
	# A fresh preview while a real paid site exists must not cancel/refund that site.
	game._select([builder]); game._start_build("house")
	game.build_preview_held=true
	check("paid_site:fresh_preview",game.build_mode=="house" and is_instance_valid(game.ghost))
	game._select_group("scout")
	var unchanged=not site.is_empty()
	for field in saved: unchanged=unchanged and site[field]==saved[field]
	check("paid_site:selection_does_not_cancel",unchanged and game.economy.bank_milli(0)==bank and game.commands.is_empty())
	game._confirm_build()
	check("paid_site:stale_confirm_is_noop",game.commands.is_empty() and game.economy.bank_milli(0)==bank)
func run():
	var args=OS.get_cmdline_user_args()
	if args.size()!=1 or FileAccess.file_exists(args[0]):
		push_error("One fresh external report path required"); quit(2); return
	report_path=args[0]
	root.size=Vector2i(390,844)
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	await settle()
	check("identity:build",game.Rules.BUILD_ID==EXPECTED_BUILD)
	check("identity:game_source",FileAccess.get_sha256("res://scripts/game.gd")==GAME_SHA)
	for kind in ["army","scout","home","empty","same","different"]:
		await selection_case(kind,true)
	await selection_case("scout",false)
	await negative_controls()
	await confirm_and_paid_site()
	var failed=0
	for row in rows:
		if not row["pass"]: failed+=1
	var result={"schema":1,"suite":"selection_preview_cancel_native","build":game.Rules.BUILD_ID,"game_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"runtime_manifest_sha256":FileAccess.get_sha256("res://reports/build-manifest.json"),"contract_sha256":FileAccess.get_sha256(get_script().resource_path),"source_lock_sha256":FileAccess.get_sha256(get_script().resource_path.get_base_dir().path_join("source_lock.json")),"scope":"Native method/state integration at 390x844; controlled pointer-handler calls; not GUI dispatch, render, physical phone, or full-match acceptance","checks":rows,"passed":rows.size()-failed,"failed":failed}
	var file=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null: push_error("Report output failed"); quit(2); return
	file.store_string(JSON.stringify(result,"  ")+"\n"); file.close()
	game.free()
	quit(0 if failed==0 else 1)
