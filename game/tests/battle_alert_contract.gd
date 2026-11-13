extends SceneTree
# ENGINE_UNRUN: controlled real combat settlement + direct UI callback assertions.
# Not routed touch/mouse, natural battle, physical-phone or rendered acceptance.
const Rules=preload("res://scripts/rules.gd")
var game
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func _initialize(): call_deferred("run")
func run():
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	game._test_reset(); game.set_process(false); game.test_mode=true; game.ai_enabled=false
	await process_frame
	var victim=game._first(0,"villager")
	var raider=game._first(1,"scout")
	var keep=game._first(0,"town_center")
	check("controlled actors exist",not victim.is_empty() and not raider.is_empty())
	if victim.is_empty() or raider.is_empty(): game.queue_free(); quit(2); return
	# Explicit controlled setup for one lethal normal attack, not earned match progress.
	victim.hp=1; game._set_stance(victim,"STOP")
	raider.pos=victim.pos+Vector3(1,0,0); raider.cooldown_ticks=0
	game._update_vision(false); game._order(raider,"attack",victim.id)
	var victim_position=victim.pos
	game._tick(Rules.TICK)
	var alert=game.battle_alerts.peek(game.tick_count)
	check("normal settled lethal own damage records alert",not victim.alive and not alert.is_empty() and alert.position==victim_position and alert.kind=="villager")
	if alert.is_empty(): game.queue_free(); quit(2); return
	game._select([keep.id]); game._update_hud()
	var selected_before=game.selected.duplicate(); var command_before=game.commands.duplicate(true)
	game.build_mode="house"; game.build_preview_held=true; game.touch_command=true
	game._focus_attack_alert()
	check("explicit focus acknowledges once",game.battle_alerts.peek(game.tick_count).is_empty())
	check("focus preserves selection and queued orders",game.selected==selected_before and game.commands==command_before)
	check("focus cancels unfinished placement and targeting",game.build_mode.is_empty() and not game.build_preview_held and not game.touch_command)
	var focus=game.camera_focus
	game._focus_attack_alert()
	check("repeat activation is no-op",game.camera_focus==focus and game.commands==command_before)
	var sample={"team":0,"alive":true,"category":"building","kind":"house","pos":Vector3(20,0,20)}
	game.battle_alerts.record_hit(sample,1.0,game.tick_count); game._refresh_attack_alert()
	var stale=game.attack_alert_button.get_meta("alert_sequence")
	# Synthetic registered GUI press, not evidence of native event routing.
	game.gui_touch_press[91]={"button":weakref(game.attack_alert_button),"origin":Vector2.ZERO,"valid":true}
	game.tick_count+=240
	game.battle_alerts.record_hit({"team":0,"alive":true,"category":"building","kind":"tower","pos":Vector3(-20,0,20)},1.0,game.tick_count)
	game._refresh_attack_alert()
	check("new destination retires previous GUI ownership",not game.gui_touch_press.has(91) and game.attack_alert_button.get_meta("alert_sequence")!=stale)
	game.attack_alert_button.set_meta("alert_sequence",stale)
	game.build_mode="house"; game.build_preview_held=true
	game._focus_attack_alert()
	check("stale activation preserves pending intent",game.build_mode=="house" and game.build_preview_held and game.camera_focus==focus)
	game.battle_alerts.reset(); game._refresh_attack_alert()
	check("reset removes pending indicator",not game.attack_alert_button.visible and game.battle_alerts.peek(game.tick_count).is_empty())
	check("economy remains conserved after alert navigation",game.economy.audit().ok)
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"battle_alert_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"scope":"ENGINE_UNRUN: controlled combat and direct callbacks, no routed input","source_sha256":FileAccess.get_sha256("res://scripts/game.gd")}))
	game.queue_free(); quit(1 if failed else 0)
