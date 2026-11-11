extends SceneTree
# Prepared native control contract; never executed by file-only preparation.
# Fixed world hit-testing is synthetic. Input routing/rendering needs phone test.
class ControlFixture:
	extends "res://scripts/game.gd"
	func _world_at(_screen): return Vector3.ZERO
	func _pick(_screen,_allow_enemy=true): return -1
var checks=0
var failures=0
func check(label,ok):
	checks+=1
	if not ok: failures+=1; push_error(label)
func _initialize():
	var game=ControlFixture.new()
	game.actions=HBoxContainer.new()
	var record={"id":1,"owned":true,"alive":true,"team":0,"category":"unit","kind":"scout","built":true}
	game.faction_views[0].current={1:record}
	game.selected=[1]
	game._rebuild_actions([record])
	for pair in [["停止","stop"],["守備","defend"]]:
		var button
		for child in game.actions.get_children():
			if child.text==pair[0]: button=child
		check("existing button "+pair[1],is_instance_valid(button))
		if not is_instance_valid(button): continue
		game.commands.clear(); game.touch_command=true
		# A concurrent world press may outlive the explicit HUD action.
		game.all_touch_ids=[4]; game.touch_points={4:Vector2(200,200)}
		game.touch_press_epochs={4:9}; game.dragging=true
		button.pressed.emit()
		check(pair[1]+" clears targeting and held world pointer",not game.touch_command and game.touch_points.is_empty() and not game.dragging and game.canceled_touch_ids.has(4))
		check(pair[1]+" selection preserved",game.selected==[1])
		check(pair[1]+" ordinary queued action only",game.commands.size()==1 and game.commands[0].type==pair[1] and game.commands[0].ids==[1] and game.commands[0].team==0)
		game._tap(Vector2(200,200),true)
		check(pair[1]+" next empty-ground tap is not a replacement order",game.commands.size()==1 and game.selected==[1])
		game.touch_command=true
		game.order_marker=Node3D.new()
		game._tap(Vector2(200,200),true)
		check(pair[1]+" explicitly rearmed command still works",game.commands.size()==2 and game.commands[1].type=="order" and not game.touch_command)
		game.order_marker.free()
	game.commands.clear(); game.touch_command=true
	var key=InputEventKey.new(); key.physical_keycode=KEY_X; key.pressed=true
	game._unhandled_input(key)
	check("X shares stance cancellation",not game.touch_command and game.commands.size()==1 and game.commands[0].type=="stop")
	game.commands.clear(); game.touch_command=true; game.build_mode="house"; game.build_preview_held=true
	game._unhandled_input(key)
	check("X preserves unrelated build preview",game.build_mode=="house" and game.build_preview_held and game.commands.size()==1)
	game.build_mode=""; game.build_preview_held=false
	for mode in ["box","rally"]:
		game.commands.clear(); game.touch_command=true; game.box_select_mode=mode=="box"; game.rally_building=8 if mode=="rally" else -1
		game._unhandled_input(key)
		check("X preserves unrelated "+mode,game.touch_command and game.box_select_mode==(mode=="box") and game.rally_building==(8 if mode=="rally" else -1) and game.commands.size()==1)
	game.box_select_mode=false; game.rally_building=-1
	for blocked in ["paused","game_over"]:
		game.commands.clear(); game.set(blocked,true); game.touch_command=true
		game._submit_selected_stance("stop")
		check(blocked+" still rejects command",game.commands.is_empty() and game.touch_command)
		game.set(blocked,false)
	game.commands.clear(); game.selected=[]; game._submit_selected_stance("defend")
	check("empty selection left to existing authority rejection",game.commands.size()==1 and game.commands[0].ids.is_empty())
	game.actions.free(); game.free()
	print("STANCE_TARGET_CANCEL_CONTRACT %d/%d (synthetic control fixture)" % [checks-failures,checks])
	quit(1 if failures else 0)
