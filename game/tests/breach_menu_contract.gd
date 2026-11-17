extends SceneTree
var checks=[]
func check(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
func settle():await process_frame;await process_frame
func run():
 root.size=Vector2i(960,640)
 var shell=load("res://main_menu.tscn").instantiate();root.add_child(shell);await settle()
 var dir="/tmp/breach-menu-"+str(Time.get_ticks_usec());DirAccess.make_dir_absolute(dir)
 shell.checkpoint_path=dir+"/ordinary.bin";shell.expedition_checkpoint_path=dir+"/expedition.bin";shell.auto_checkpoint_path=dir+"/auto.bin"
 for path in [shell.checkpoint_path,shell.expedition_checkpoint_path,shell.auto_checkpoint_path]:
  var f=FileAccess.open(path,FileAccess.WRITE);f.store_string("untouched existing slot");f.close()
 shell.buttons.get_node("StartMatchButton").pressed.emit();shell.buttons.get_node("BattleGroup3").pressed.emit()
 check("mission is selectable in scenario group",shell.buttons.has_node("ChooseBattle_breach"))
 for size in [Vector2i(640,360),Vector2i(320,568),Vector2i(390,844)]:
  root.size=size;shell._layout();await settle()
  var fit=true
  for button in shell.buttons.get_children():fit=fit and Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()) and button.size.y>=44
  check("scenario choices fit "+str(size),fit)
 shell.buttons.get_node("ChooseBattle_breach").pressed.emit();await settle()
 check("setup discloses no saving and scripted enemy",shell.description.text.contains("暫不支援存檔") and shell.description.text.contains("無經濟AI"))
 shell.buttons.get_node("LaunchMatchButton").pressed.emit();await settle()
 var g=shell.match_node;g.set_process(false);g.test_mode=true
 check("normal launch creates authored breach",g.skirmish_mode=="breach" and g.breach_mission.stage==0)
 shell._open_menu();shell._show_page("checkpoint");await settle()
 check("checkpoint page excludes save action",not shell.buttons.has_node("SaveCheckpointButton") and shell.description.text.contains("攻城突破暫不支援存檔"))
 shell._resume_match();await settle();g.set_process(false);g.test_mode=true;g._submit("surrender");g._tick(.05)
 check("mission has actual defeat report and replay action",g.game_over and g.outcome=="defeat" and g.end_actions.has_node("ReplayMatchButton"))
 g.end_actions.get_node("ReplayMatchButton").pressed.emit();await settle()
 var replay=shell.match_node;replay.set_process(false);replay.test_mode=true
 check("replay rebuilds same mission from start",replay!=g and replay.skirmish_mode=="breach" and replay.breach_mission.stage==0 and not replay.game_over)
 check("all existing slot bytes preserved",[shell.checkpoint_path,shell.expedition_checkpoint_path,shell.auto_checkpoint_path].all(func(path):return FileAccess.get_file_as_string(path)=="untouched existing slot"))
 shell.free();await settle()
 print(JSON.stringify({"suite":"breach_menu_contract","checks":checks,"failed":checks.filter(func(c):return not c.passed).size(),"scope":"Native real menu signals, viewport geometry and isolated slot preservation; no physical-device screenshot claim."}))
 quit(1 if checks.any(func(c):return not c.passed) else 0)
