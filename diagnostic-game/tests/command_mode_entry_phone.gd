extends SceneTree
# PREPARED ONLY: real HUD callbacks and synthetic routed viewport touches.
# No physical-phone, browser, render-fit, or native acceptance is claimed.
var game
var checks=[]
func _initialize(): call_deferred("run")
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func settle():
	for i in 4: await process_frame
func touch(p,pressed,index=0):
	var event=InputEventScreenTouch.new(); event.position=p; event.index=index; event.pressed=pressed
	root.push_input(event,false)
func tap(p):
	touch(p,true); await process_frame; touch(p,false); await settle()
func reveal_menu_button(button):
	var ancestor=button.get_parent()
	while is_instance_valid(ancestor) and not ancestor is ScrollContainer:
		ancestor=ancestor.get_parent()
	if not is_instance_valid(ancestor): return false
	# Explicitly scroll the real menu before routed touch; never tap clipped content.
	ancestor.ensure_control_visible(button)
	await settle()
	return button.is_visible_in_tree() and ancestor.is_visible_in_tree() and ancestor.get_global_rect().encloses(button.get_global_rect()) and root.get_visible_rect().encloses(button.get_global_rect())
func run():
	root.size=Vector2i(390,844)
	game=load("res://main.tscn").instantiate(); root.add_child(game); game.test_mode=true
	await settle()
	var worker=-1
	for record in game.faction_views[0].records().values():
		if record.owned and record.alive and record.kind=="villager": worker=record.id; break
	check("owned worker fixture",worker>=0)
	if worker<0: quit(1); return
	game._select([worker]); game._start_build("house"); await settle()
	game.build_preview_held=true
	var queued=game.commands.duplicate(true)
	await tap(game.compact_menu_button.get_global_rect().get_center())
	check("menu preserves preview before deliberate choice",game.build_mode=="house")
	var move
	for button in game.compact_menu.find_children("*","Button",true,false):
		if button.text=="移動／攻擊": move=button
	check("Move Attack present",is_instance_valid(move))
	if not is_instance_valid(move): quit(1); return
	var move_visible=await reveal_menu_button(move)
	check("Move Attack is fully inside visible menu scroll rectangle",move_visible)
	if not move_visible: quit(1); return
	await tap(move.get_global_rect().get_center())
	check("menu Move Attack replaces build preview",game.touch_command and game.build_mode.is_empty() and not game.build_preview_held and game.ghost==null and not game.compact_menu.visible and game.selected==[worker] and game.commands==queued)
	await tap(game.touch_button.get_global_rect().get_center())
	check("pinned toggle off does not issue order",not game.touch_command and game.commands==queued)
	# Reused touch ID before deferred epoch cleanup, inherited phone-edge scenario.
	var p=game.touch_button.get_global_rect().get_center()
	touch(p,true); touch(p,false); touch(p,true); touch(p,false); await settle()
	check("rapid reused ID on then off",not game.touch_command and game.commands==queued and game.touch_press_epochs.is_empty())
	# A held world pointer must not survive a deliberate command replacement.
	var world=Vector2(160,300)
	touch(world,true,3); game._start_build("house"); game._start_unit_command()
	touch(world,false,3); await settle()
	check("retired held release cannot submit",game.touch_command and game.commands==queued and game.touch_points.is_empty())
	game._cancel_mode(); game._select([])
	game._toggle_compact_menu(); await settle()
	move_visible=await reveal_menu_button(move)
	check("reopened Move Attack is fully inside visible menu scroll rectangle",move_visible)
	if not move_visible: quit(1); return
	await tap(move.get_global_rect().get_center())
	check("menu empty selection cannot arm",not game.touch_command and game.commands==queued)
	var failed=checks.filter(func(item): return not item.passed)
	print(JSON.stringify({"suite":"command_mode_entry_phone","build":game.Rules.BUILD_ID,"source_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"suite_sha256":FileAccess.get_sha256(get_script().resource_path),"checks":checks,"scope":"Synthetic routed native contract, prepared only until executed separately"}))
	quit(1 if failed.size()>0 else 0)
