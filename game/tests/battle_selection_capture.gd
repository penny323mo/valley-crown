extends SceneTree
var outputs=[]
func _initialize():call_deferred("run")
func shot(name):
 await process_frame;await process_frame
 if DisplayServer.get_name()=="headless":return
 await RenderingServer.frame_post_draw
 outputs.append({"name":name,"error":root.get_texture().get_image().save_png("/tmp/capture/"+name+".png")})
func run():
 DirAccess.make_dir_recursive_absolute("/tmp/capture")
 var shell=load("res://main_menu.tscn").instantiate();root.add_child(shell);await process_frame
 var dir="/tmp/battle-flow-capture-"+str(Time.get_ticks_usec());DirAccess.make_dir_absolute(dir)
 shell.checkpoint_path=dir+"/ordinary.bin";shell.expedition_checkpoint_path=dir+"/expedition.bin"
 for size in [Vector2i(640,360),Vector2i(320,568)]:
  root.size=size;shell._show_page("battle_groups")
  await shot("battle-selection-"+str(size.x))
  shell.buttons.get_node("BattleGroup0").pressed.emit()
  await shot("battle-economy-options-"+str(size.x))
  shell.buttons.get_node("BattleOptionsBackButton").pressed.emit();shell.buttons.get_node("BattleGroup2").pressed.emit()
  shell.buttons.get_node("ChooseBattle_fortress").pressed.emit()
  await shot("battle-briefing-"+str(size.x))
 root.size=Vector2i(640,360)
 shell.buttons.get_node("LaunchMatchButton").pressed.emit();await process_frame;await process_frame
 var g=shell.match_node;g.set_process(false);g.test_mode=true
 # Genuine new match and ordinary surrender, not a claimed natural campaign win.
 g._submit("surrender");g._tick(.05);g._layout_ui()
 await shot("battle-result-actions-640")
 root.size=Vector2i(320,568);g._layout_ui()
 await shot("battle-result-actions-320")
 g.end_actions.get_node("ReconfigureMatchButton").pressed.emit()
 await shot("battle-reconfigure-320")
 var ok=g.game_over and g.outcome=="defeat" and shell.match_node==g and shell.page=="battle_groups"
 print(JSON.stringify({"suite":"battle_selection_capture","routing_ok":ok,"outputs":outputs,"scope":"Real native selection and briefing UI; actual new fortress match intentionally surrendered to show terminal actions, not a naturally won campaign or physical phone test"}))
 shell.queue_free();await process_frame;quit(0 if ok else 1)
