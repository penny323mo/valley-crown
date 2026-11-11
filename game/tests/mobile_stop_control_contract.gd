extends SceneTree
# Synthetic control fixture. Real engine execution is required separately;
# this does not establish rendered fit, browser or physical-phone acceptance.
class ControlledHUD:
	extends "res://scripts/game.gd"
	# This fixture owns only synthetic controls; the phone suite uses real HUD.
	var hud_updates=0
	func _update_hud(): hud_updates+=1
var game
var checks=[]
func _initialize(): call_deferred("run")
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func run():
	game=ControlledHUD.new()
	var row=HBoxContainer.new(); root.add_child(row)
	game.actions=HBoxContainer.new(); row.add_child(game.actions)
	game.compact_unit_tools=HBoxContainer.new(); row.add_child(game.compact_unit_tools)
	game.compact_cancel_button=game._button("取消",game._cancel_mode,54)
	game.compact_unit_tools.add_child(game.compact_cancel_button)
	var record={"id":1,"owned":true,"alive":true,"team":0,"category":"unit","kind":"scout","built":true}
	game.faction_views[0].current={1:record}; game.selected=[1]
	game.compact_ui=true; game._rebuild_actions([record]); game._refresh_stop_button()
	var button=game.stop_button
	check("one compact Stop in auxiliary container",button.get_parent()==game.compact_unit_tools and button.text=="停止")
	check("Stop keeps existing minimum target",button.custom_minimum_size==Vector2(54,46))
	check("no duplicate Stop in strip",game.actions.get_children().filter(func(child): return child.text=="停止").is_empty())
	game.gui_touch_press={4:{"button":weakref(button),"origin":Vector2.ZERO,"valid":true}}
	game.touch_command=true; game._refresh_stop_button()
	check("targeting moves same Stop back to strip",game.stop_button==button and button.get_parent()==game.actions)
	check("reparent retires old touch ownership without issuing command",game.gui_touch_press.is_empty() and game.commands.is_empty())
	var names=[]
	for child in game.actions.get_children(): names.append(child.text)
	check("targeting preserves Cargo Stop Defend ordering",names==["取消選取","交付資源","停止","守備"])
	game.gui_touch_press={4:{"button":weakref(button),"origin":Vector2.ZERO,"valid":true}}
	game.touch_command=false; game._refresh_stop_button()
	check("returning same Stop retires old touch ownership",button.get_parent()==game.compact_unit_tools and game.gui_touch_press.is_empty() and game.commands.is_empty())
	for blocked in ["paused","game_over"]:
		game.set(blocked,true); game._refresh_stop_button()
		check(blocked+" disables pinned Stop",button.disabled)
		game._submit_selected_stance("stop")
		check(blocked+" ordinary submission remains rejected",game.commands.is_empty())
		game.set(blocked,false)
	game._refresh_stop_button()
	var hud_updates=game.hud_updates
	game.all_touch_ids=[4]; game.touch_points={4:Vector2(200,200)}
	game.touch_press_epochs={4:9}; game.dragging=true
	button.pressed.emit(); button.pressed.emit()
	check("ordinary Stop retires held pointers without rebuilding HUD",game.hud_updates==hud_updates and game.touch_points.is_empty() and not game.dragging and game.canceled_touch_ids.has(4))
	check("each explicit tap submits only an ordinary Stop",game.commands.size()==2 and game.commands.all(func(command): return command.type=="stop" and command.ids==[1] and command.team==0))
	check("repeated tap identifiers remain distinct",game.commands[0].command_id!=game.commands[1].command_id)
	game.commands.clear(); game.compact_ui=false; game._refresh_stop_button()
	check("desktop keeps original strip Stop",button.get_parent()==game.actions)
	game.compact_ui=true; game._refresh_stop_button()
	game.selected=[2]; record=record.duplicate(); record.id=2; game.faction_views[0].current={2:record}
	game._rebuild_actions([record]); game._refresh_stop_button()
	check("replacement selection cannot retain old Stop instance",game.stop_button!=button and button.is_queued_for_deletion() and button.get_parent()==null)
	for mode in ["build","box","rally","empty"]:
		game.build_mode="house" if mode=="build" else ""; game.box_select_mode=mode=="box"; game.rally_building=2 if mode=="rally" else -1
		game._rebuild_actions([] if mode=="empty" else [record]); game._refresh_stop_button()
		check(mode+" has no Stop control",not is_instance_valid(game.stop_button))
	check("layout changes never submit commands",game.commands.is_empty())
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"mobile_stop_control_contract","build":game.Rules.BUILD_ID,"checks":checks,"failed":failed,"source_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"scope":"Synthetic control fixture, not rendered or physical-device acceptance"}))
	row.free(); game.free(); quit(1 if failed else 0)
