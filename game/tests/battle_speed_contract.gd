extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);await process_frame
 game.ai_enabled=false;game.test_mode=false;game.paused=false;game.application_focused=true;game.application_suspended=false;game.discard_return_delta=false
 check("new match starts at normal speed",game.battle_speed==1.0)
 game.compact_menu.show();game._set_shortcut_category("settings")
 check("speed control reachable from settings",game.battle_speed_button.is_visible_in_tree())
 var before=game.commands.duplicate(true);var tick=game.tick_count
 game._cycle_battle_speed()
 check("normal cycles to double speed",game.battle_speed==2.0)
 game._process(Rules.TICK)
 check("double speed advances two fixed ticks",game.tick_count==tick+2)
 game.compact_menu.show();game._cycle_battle_speed();tick=game.tick_count
 check("double cycles to half speed",game.battle_speed==0.5)
 game._process(Rules.TICK)
 check("half speed preserves fractional tick without early simulation",game.tick_count==tick and is_equal_approx(game.tick_accumulator,Rules.TICK/2))
 game._process(Rules.TICK)
 check("two half speed frames advance one tick",game.tick_count==tick+1)
 game.compact_menu.show();game._cycle_battle_speed()
 check("half cycles back to normal",game.battle_speed==1.0)
 check("speed selection does not issue game commands",game.commands==before)
 game.paused=true;game.compact_menu.show();game._cycle_battle_speed();tick=game.tick_count
 game._process(0.1)
 check("speed may change during pause without advancing",game.battle_speed==2.0 and game.tick_count==tick and game.tick_accumulator==0)
 game.paused=false;game.application_suspended=true;game._process(0.1)
 check("suspended app never fast forwards",game.tick_count==tick)
 game.application_suspended=false;game.discard_return_delta=true;game._process(20.0)
 check("return delta is discarded before speed scaling",game.tick_count==tick)
 game.game_over=true;game.compact_menu.show();game._cycle_battle_speed()
 check("finished battle cannot change speed",game.battle_speed==2.0)
 game.game_over=false;game._test_reset();game.test_mode=false;game.ai_enabled=false;game.paused=false;game.discard_return_delta=false
 check("new battle resets to one times",game.battle_speed==1.0)
 for i in 10:game._process(Rules.TICK)
 var normal_bank=game.economy.snapshot();var normal_time=game.game_time;var normal_positions=[]
 for ent in game.entities:normal_positions.append(ent.pos)
 game._test_reset();game.test_mode=false;game.ai_enabled=false;game.paused=false;game.discard_return_delta=false;game.battle_speed=2.0
 for i in 5:game._process(Rules.TICK)
 var positions=[]
 for ent in game.entities:positions.append(ent.pos)
 check("equal simulation time keeps identical economy ledger",game.economy.snapshot()==normal_bank)
 check("equal simulation time keeps identical unit positions",positions==normal_positions)
 check("match clock measures simulated time",is_equal_approx(game.game_time,normal_time))
 game._update_hud()
 check("nonstandard speed visible in battle clock",game.time_label.text.contains("2×"))
 check("speed leaves economy conserved",game.economy.audit().ok)
 game.queue_free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"battle_speed_contract","checks":checks,"failed":failed,"scope":"Native real frame accumulator and settings actions; not physical phone performance"}))
 quit(1 if failed else 0)
