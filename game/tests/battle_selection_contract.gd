extends SceneTree
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var shell=load("res://main_menu.tscn").instantiate();root.add_child(shell);await process_frame
 var dir="/tmp/battle-selection-"+str(Time.get_ticks_usec());DirAccess.make_dir_absolute(dir)
 shell.checkpoint_path=dir+"/ordinary.bin";shell.expedition_checkpoint_path=dir+"/expedition.bin"
 for path in [shell.checkpoint_path,shell.expedition_checkpoint_path]:
  var f=FileAccess.open(path,FileAccess.WRITE);f.store_string("isolated untouched sentinel");f.close()
 shell.buttons.get_node("StartMatchButton").pressed.emit()
 check("start enters selection without starting game",shell.page=="battle_groups" and not is_instance_valid(shell.match_node))
 check("catalogue contains ten distinct configurations",shell.BattleSelection.OPTIONS.size()==10)
 for option in shell.BattleSelection.OPTIONS:
  shell._show_page("battle_groups");shell.buttons.get_node("BattleGroup"+str(option.group)).pressed.emit()
  shell.buttons.get_node("ChooseBattle_"+option.id).pressed.emit()
  check("selection installs briefing "+option.id,shell.page=="setup" and shell.selected_mode==option.mode and shell.selected_victory_mode==option.victory and shell.mode_title.text==option.title)
  check("briefing includes opening enemy victory defeat "+option.id,shell.description.text.contains("開局\n") and shell.description.text.contains("敵軍\n") and shell.description.text.contains("勝利\n") and shell.description.text.contains("失敗\n"))
  check("selection does not start or destroy previous battle "+option.id,not shell.transition_busy and (not is_instance_valid(shell.match_node) or shell.menu_layer.visible))
  shell.buttons.get_node("LaunchMatchButton").pressed.emit();await process_frame;await process_frame
  var g=shell.match_node;g.set_process(false);g.test_mode=true
  check("launch uses exact supported configuration "+option.id,g.skirmish_mode==option.mode and g.victory_mode==option.victory)
  shell._open_menu()
 var g=shell.match_node;shell._resume_match();await process_frame;await process_frame;g.set_process(false);g.test_mode=true
 g._submit("surrender");g._tick(.05)
 check("ordinary surrender produces real terminal result",g.game_over and g.outcome=="defeat")
 g.end_actions.get_node("ReconfigureMatchButton").pressed.emit()
 check("terminal reconfigure opens selector without new match",shell.page=="battle_groups" and shell.match_node==g and not shell.transition_busy)
 shell.buttons.get_node("BattleGroupsBackButton").pressed.emit()
 check("cancel reconfiguration retains terminal result",shell.match_node==g and shell.page=="home" and g.game_over)
 shell._review_finished_match();await process_frame;await process_frame;g.end_actions.get_node("EndMainMenuButton").pressed.emit()
 check("terminal main menu never starts battle",shell.match_node==g and shell.page=="home" and not shell.transition_busy)
 shell._review_finished_match();await process_frame;await process_frame;g.end_actions.get_node("ReplayMatchButton").pressed.emit();await process_frame;await process_frame
 var replay=shell.match_node;replay.set_process(false);replay.test_mode=true
 check("same-configuration replay creates fresh expedition",replay!=g and replay.skirmish_mode=="expedition" and replay.victory_mode=="conquest" and not replay.game_over)
 replay._submit("surrender");replay._tick(.05)
 for size in [Vector2i(640,360),Vector2i(320,568),Vector2i(390,844)]:
  root.size=size
  replay._layout_ui();await process_frame;await process_frame
  var fit=true
  for button in replay.end_actions.get_children():fit=fit and Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()) and button.size.y>=44
  check("terminal actions fit "+str(size),fit)
  shell._open_menu()
  for page in ["battle_groups","battle_options","setup"]:
   shell.battle_group=0;shell._show_page(page);await process_frame;await process_frame
   fit=true
   for button in shell.buttons.get_children():fit=fit and Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()) and button.size.y>=44
   check(page+" actions fit "+str(size),fit)
  shell._review_finished_match();await process_frame;await process_frame
 check("all menu and replay actions leave both slots untouched",FileAccess.get_file_as_string(shell.checkpoint_path)=="isolated untouched sentinel" and FileAccess.get_file_as_string(shell.expedition_checkpoint_path)=="isolated untouched sentinel")
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"battle_selection_contract","checks":checks,"failed":failed,"scope":"Native direct selection of ten supported configurations, terminal replay and cancel routing, viewport geometry and isolated slot preservation; no new AI difficulty, migration or physical-device claim"}))
 shell.queue_free();await process_frame;quit(1 if failed else 0)
