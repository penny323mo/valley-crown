extends SceneTree
const Store=preload("res://scripts/checkpoint_store.gd")
var checks=[]
func check(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
func click(button):
 var p=button.get_global_rect().get_center()
 var e=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.position=p;e.pressed=true;root.push_input(e);await process_frame
 e=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.position=p;e.pressed=false;root.push_input(e);await process_frame
func run():
 root.size=Vector2i(960,640)
 var shell=load("res://main_menu.tscn").instantiate();shell.checkpoint_path="/tmp/v88-menu-"+str(Time.get_ticks_usec())+".bin";root.add_child(shell);await process_frame
 shell._choose_battle("standard");await process_frame
 check("standard default visible before launch",shell.selected_difficulty=="standard" and shell.buttons.has_node("ChooseDifficultyButton") and shell.description.text.contains("90 秒"))
 shell.buttons.get_node("ChooseDifficultyButton").pressed.emit();await process_frame
 await click(shell.buttons.get_node("DifficultyEasyButton"))
 check("routed native choice selects lower pressure without launch",shell.page=="setup" and shell.selected_difficulty=="easy" and not is_instance_valid(shell.match_node))
 check("lower pressure briefing is not contradictory",shell.description.text.contains("180 秒") and not shell.description.text.contains("90 秒") and shell.description.text.contains("最多 5 兵"))
 shell.buttons.get_node("ChooseLayoutButton").pressed.emit();shell.buttons.get_node("LayoutWoodlandButton").pressed.emit()
 check("map selection preserves pressure",shell.selected_layout=="woodland" and shell.selected_difficulty=="easy")
 shell._show_page("home");shell._show_page("setup")
 check("return to setup preserves pending pressure",shell.selected_difficulty=="easy")
 shell.buttons.get_node("LaunchMatchButton").pressed.emit();await process_frame;await process_frame
 var g=shell.match_node;g.set_process(false);g.test_mode=true
 check("launch installs actual pressure and layout",g.ai_difficulty=="easy" and g.layout_id=="woodland")
 shell.selected_difficulty="standard";shell._open_menu()
 check("pause shows actual match pressure not pending choice",shell.description.text.contains("本局電腦：較低襲擊壓力"))
 shell._show_page("checkpoint");shell._save_checkpoint()
 var saved=Store.read_slot(g.Rules.BUILD_ID,shell.checkpoint_path)
 check("actual local save records pressure",saved.ok and saved.data.game.ai_difficulty=="easy")
 shell.selected_difficulty="standard";shell._restore_checkpoint();await process_frame
 var loaded=shell.match_node;loaded.set_process(false);loaded.test_mode=true
 check("menu load synchronizes saved pressure and pauses",loaded.ai_difficulty=="easy" and shell.selected_difficulty=="easy" and loaded.paused and loaded.layout_id=="woodland")
 shell._restart_match();await process_frame;await process_frame
 var restarted=shell.match_node;restarted.set_process(false);restarted.test_mode=true
 check("restart retains pressure instead of defaulting",restarted.ai_difficulty=="easy" and restarted.layout_id=="woodland" and restarted!=loaded)
 shell._open_menu();shell._choose_battle("pressure")
 check("unsupported battle hides pressure selector and resets standard",shell.selected_difficulty=="standard" and not shell.buttons.has_node("ChooseDifficultyButton"))
 shell._choose_battle("standard");shell.buttons.get_node("ChooseDifficultyButton").pressed.emit();shell.buttons.get_node("DifficultyStandardButton").pressed.emit()
 check("explicit standard restores original briefing",shell.selected_difficulty=="standard" and shell.description.text.contains("90 秒"))
 for size in [Vector2i(390,844),Vector2i(640,360),Vector2i(320,568)]:
  root.size=size;shell._show_page("difficulty");await process_frame;await process_frame
  var fit=true
  for button in shell.buttons.get_children():fit=fit and Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()) and button.size.y>=44
  check("difficulty choices fit native viewport "+str(size),fit)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"difficulty_menu_contract","checks":checks,"failed":failed,"scope":"Native menu signals plus actual routed difficulty button, actual local save/load/restart and viewport layout. Not browser or physical phone."}))
 quit(1 if failed else 0)
