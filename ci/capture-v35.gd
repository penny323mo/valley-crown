extends SceneTree
const OUT="/tmp/capture/"
func _initialize():call_deferred("run")
func shot(game,name):
 game._update_hud();game._layout_ui();game._camera_update()
 await process_frame
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image();var error=image.save_png(OUT+name+".png")
 print("CAPTURE ",name," ",image.get_width(),"x",image.get_height()," ",error)
 return error==OK
func run():
 root.size=Vector2i(640,360)
 var game=load("res://main.tscn").instantiate();game.skirmish_mode="fortress";root.add_child(game);game.set_process(false);game.ai_enabled=false
 await process_frame
 game.paused=false;game.application_focused=true;game.application_suspended=false;game._skip_tutorial()
 game._update_vision();game._update_visuals(0.0);game._update_hud();game._layout_ui();game._camera_update()
 game.compact_menu.show();game._set_shortcut_category("settings")
 game._cycle_battle_speed()
 var ok=await shot(game,"native-settings-double-battle-pace")
 game._cycle_battle_speed()
 ok=await shot(game,"native-settings-half-battle-pace") and ok
 print(JSON.stringify({"build":game.Rules.BUILD_ID,"scope":"Native controlled fortress fixture, actual settings cycling; not physical phone performance or natural battle timing"}))
 game.queue_free();quit(0 if ok else 1)
