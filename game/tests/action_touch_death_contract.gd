extends SceneTree
# ENGINE_UNRUN. Synthetic UI/entity fixture with direct handler calls, not routed
# touch, rendering or physical-phone acceptance. Actual kill/HUD/rebuild/touch/
# submit/cancel methods are used. World navigation, visibility and layout are
# fixture-controlled; no scene, importer, simulation or native run occurs here.
class ControlledGame:
	extends "res://scripts/game.gd"
	var nav_rebuilds=0
	func _ready(): pass
	func _process(_delta): pass
	func _layout_ui(): pass
	func _refresh_tutorial(): pass
	func _navigation_rebuild(): nav_rebuilds+=1
	func _visible_to(ent,team): return ent.get("seen",false) or ent.team==team
var game
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func _initialize(): call_deferred("run")
func make_entity(id,kind,category,team,seen=true):
	var node=Node3D.new(); game.add_child(node)
	return {"id":id,"kind":kind,"category":category,"team":team,"owned":team==0,
		"alive":true,"built":true,"state":"idle","mode":"IDLE","seen":seen,
		"node":node,"body":node,"pos":Vector3.ZERO,"queue":[],"path":PackedVector3Array(),
		"hp":100,"max_hp":100,"remembered":false,"cargo_milli":0}
func sync_owned():
	var current={}
	for ent in game.entities:
		if ent.alive and ent.team==0:
			# Test-only value projection. Never publish Nodes into FactionView.
			var record=ent.duplicate(); record.erase("node"); record.erase("body")
			current[ent.id]=record
	game.faction_views[0].current=current
func find_button(prefix):
	for button in game.actions.get_children():
		if button.text.begins_with(prefix): return button
	return null
func press(button):
	button.size=Vector2(160,64)
	game.all_touch_ids=[7]; game.touch_press_epochs={7:1}
	var event=InputEventScreenTouch.new(); event.index=7; event.pressed=true; event.position=Vector2(12,12)
	game._button_touch_input(button,event)
func release(button,canceled=false):
	game.all_touch_ids.clear()
	var event=InputEventScreenTouch.new(); event.index=7; event.pressed=false; event.canceled=canceled; event.position=Vector2(12,12)
	game._button_touch_input(button,event)
func run():
	game=ControlledGame.new(); root.add_child(game)
	game._reset_economy(game.INITIAL_STOCKS)
	for field in ["top_resources","time_label","selection_title","selection_detail","help_label","mission_label","queue_label"]:
		var label=Label.new(); game.set(field,label); game.add_child(label)
	for field in ["pause_button","touch_button","compact_cancel_button"]:
		var button=Button.new(); game.set(field,button); game.add_child(button)
	game.actions=HBoxContainer.new(); game.add_child(game.actions)
	game.compact_unit_tools=HBoxContainer.new(); game.add_child(game.compact_unit_tools)
	check("project uses explicit touch path",not Input.emulate_mouse_from_touch and not ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch",true))
	var town=make_entity(1,"town_center","building",0)
	game.entities=[town]; game.selected=[1]; sync_owned(); game._update_hud()
	var sequence=0
	for spec in [["scout","unit",1,true],["scout","unit",1,false],["pine","resource",-1,false],["house","building",0,true]]:
		var held=find_button("訓練村民"); var old_key=game.action_key
		var victim=make_entity(10+sequence,spec[0],spec[1],spec[2],spec[3]); game.entities.append(victim)
		press(held); game._kill(victim); sync_owned(); game._update_hud()
		check("unrelated death retains action identity "+str(sequence),find_button("訓練村民")==held and game.action_key==old_key and not held.is_queued_for_deletion())
		release(find_button("訓練村民")); sequence+=1
		check("held train accepted exactly once "+str(sequence),game.commands.size()==sequence and game.commands[-1].type=="train" and game.commands[-1].building==1 and game.commands[-1].kind=="villager")
		release(held)
		check("duplicate release adds no command "+str(sequence),game.commands.size()==sequence)
	check("resource/building navigation still invalidated",game.nav_rebuilds==2)
	var held=find_button("訓練村民"); press(held)
	town.queue=[{"kind":"villager","remaining_ticks":20}]; sync_owned(); game._update_hud()
	check("queue change still replaces controls",find_button("訓練村民")!=held and held.is_queued_for_deletion())
	release(find_button("訓練村民"))
	check("old held press cannot activate changed queue",game.commands.size()==sequence)
	town.queue.clear(); sync_owned(); game._update_hud()
	held=find_button("訓練村民"); press(held); game.compact_ui=true; game._update_hud()
	check("layout change still replaces controls",find_button("訓練村民")!=held)
	release(find_button("訓練村民")); check("layout release cannot act",game.commands.size()==sequence)
	held=find_button("訓練村民"); press(held); game._kill(town); sync_owned(); game._update_hud()
	check("selected producer removed and controls rebuilt",game.selected.is_empty() and find_button("訓練村民")==null and held.is_queued_for_deletion())
	release(find_button("選取村民")); check("selected death cannot train stale producer",game.commands.size()==sequence)
	var ally=make_entity(50,"scout","unit",0); game.entities.append(ally); game.selected=[50]; game.touch_command=true
	sync_owned(); game._update_hud(); game.all_touch_ids=[8]; game.touch_press_epochs={8:1}
	game._kill(ally)
	check("last selected unit death still cancels targeting and held stream",not game.touch_command and game.selected.is_empty() and game.all_touch_ids.is_empty() and game.canceled_touch_ids.has(8))
	var producer=make_entity(51,"town_center","building",0); game.entities.append(producer); game.selected=[51]; game.rally_building=51
	sync_owned(); game._update_hud(); game._kill(producer)
	check("selected rally producer death still cancels",game.rally_building==-1 and game.selected.is_empty())
	check("death handling submits no other commands",game.commands.size()==sequence)
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"action_touch_death_contract","build":game.Rules.BUILD_ID,"checks":checks,"failed":failed,"source_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"scope":"Synthetic UI/entity contract; routed runtime and physical phone unverified"}))
	game.free(); quit(1 if failed else 0)
