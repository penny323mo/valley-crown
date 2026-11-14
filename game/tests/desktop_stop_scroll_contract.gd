extends SceneTree
class ControlledHUD:
	extends "res://scripts/game.gd"
	func _update_hud(): pass
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func _initialize():call_deferred("run")
func run():
	var game=ControlledHUD.new()
	var row=HBoxContainer.new();root.add_child(row)
	game.actions=HBoxContainer.new();row.add_child(game.actions)
	game.compact_unit_tools=HBoxContainer.new();row.add_child(game.compact_unit_tools)
	game.actions.add_child(game._button("其他",func():pass,54))
	game.stop_button=game._button("停止",func():pass,54);game.actions.add_child(game.stop_button)
	game.actions.add_child(game._button("守備",func():pass,54))
	game.compact_ui=false
	game._refresh_stop_button()
	check("missing scroll container does not prevent Stop placement",game.stop_button.get_index()==0 and game.action_scroll==null)
	game.action_scroll=ScrollContainer.new();row.add_child(game.action_scroll)
	game.action_scroll.get_h_scroll_bar().max_value=1000
	game.action_scroll.scroll_horizontal=100
	game.actions.move_child(game.stop_button,1)
	game._refresh_stop_button()
	check("desktop transition restores start of action strip",game.stop_button.get_index()==0 and game.action_scroll.scroll_horizontal==0)
	game.action_scroll.scroll_horizontal=100
	game._refresh_stop_button()
	check("ordinary HUD refresh does not steal intentional horizontal scroll",game.action_scroll.scroll_horizontal==100)
	check("layout never issues gameplay commands",game.commands.is_empty())
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"desktop_stop_scroll_contract","checks":checks,"failed":failed}))
	row.free();game.free();quit(1 if failed else 0)
