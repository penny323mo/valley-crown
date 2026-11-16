extends SceneTree
const OUT="/tmp/capture/"
func _initialize():call_deferred("run")
func shot(g,name):
 g._update_vision(false);g._publish_faction_views();g._update_visuals(0);g._update_hud();g._layout_ui();g._camera_update()
 await process_frame
 await process_frame
 if DisplayServer.get_name()=="headless":return true
 await RenderingServer.frame_post_draw
 var im=root.get_texture().get_image();var err=im.save_png(OUT+name+".png")
 print("CAPTURE ",name," ",im.get_width(),"x",im.get_height()," ",err)
 return err==OK
func run():
 root.size=Vector2i(640,360)
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.set_process(false);g.ai_enabled=false
 await process_frame
 g.paused=false;g.application_focused=true;g.application_suspended=false;g._skip_tutorial();g.commands.clear()
 g.camera_zoom=30;g.camera_focus=Vector3(-25,0,22)
 var ok=await shot(g,"native-resource-art-default-zoom30")
 g.camera_zoom=18;g.camera_focus=Vector3(-25,0,18)
 ok=(await shot(g,"native-resource-art-playable-zoom18")) and ok
 print(JSON.stringify({"build":g.Rules.BUILD_ID,"rendered":DisplayServer.get_name()!="headless","ledger_ok":g.economy.audit().ok,"scope":"Actual initial map and default starting resource quantities; only camera positioned at default30 and playable18. No asset gallery, invented screenshot, resource edits, saved files or harvested-throughput claim."}));g.queue_free();quit(0 if ok else 1)
