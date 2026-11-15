extends SceneTree
const OUT="/tmp/capture/"
func _initialize():call_deferred("run")
func shot(name):
 for i in 4:await process_frame
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image()
 var error=image.save_png(OUT+name+".png")
 print("CAPTURE ",name," ",image.get_width(),"x",image.get_height()," ",error)
 return error==OK
func run():
 root.size=Vector2i(1280,720)
 var game=load("res://main.tscn").instantiate();game.skirmish_mode="fortress";root.add_child(game);game.set_process(false)
 game.paused=true
 game._update_vision();game._update_visuals(0.0);game._update_hud();game._layout_ui();game._camera_update()
 var ok=await shot("fortress-native-overview")
 var cavalry=game._first(0,"cavalry")
 game._select([cavalry.id]);game.camera_focus=cavalry.pos;game.camera_zoom=15;game._camera_update();game._update_visuals(0.0);game._update_hud();game._layout_ui()
 ok=await shot("cavalry-native-player-zoom") and ok
 # Explicit diagnostic closeup beyond the player's normal zoom. The same live
 # game model and materials, not a fabricated image or claimed browser capture.
 game.camera_zoom=4;game.camera_focus=cavalry.pos+Vector3(0,0.6,0);game._camera_update();game._update_visuals(0.0)
 ok=await shot("cavalry-native-diagnostic-closeup") and ok
 print("SOURCE_BUILD ",game.Rules.BUILD_ID)
 game.queue_free();quit(0 if ok else 1)
