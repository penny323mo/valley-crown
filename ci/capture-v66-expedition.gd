extends SceneTree
func shot(g,focus,name,label):
 g.camera_zoom=18;g.camera_focus=focus;g._layout_ui();g._camera_update();g._update_vision();g._publish_faction_views()
 g._update_visuals(.016);g._refresh_fog();g._update_hud();g._message(label,30)
 await process_frame
 await process_frame
 if DisplayServer.get_name()=="headless":
  print("HEADLESS_CAPTURE_SKIPPED ",name)
  return OK
 await RenderingServer.frame_post_draw
 var im=root.get_texture().get_image()
 return im.save_png("/tmp/capture/"+name+".png")
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(640,360)
 DirAccess.make_dir_recursive_absolute("/tmp/capture")
 var menu=load("res://main_menu.tscn").instantiate()
 menu.checkpoint_path="user://isolated-capture-never-read.json";menu.history_path="user://isolated-history-never-read.json"
 root.add_child(menu);menu._layout();await process_frame;await process_frame
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  if root.get_texture().get_image().save_png("/tmp/capture/expedition-home.png")!=OK:quit(1);return
 menu.queue_free();await process_frame
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="expedition";root.add_child(g)
 g.test_mode=true;g.set_process(false);await process_frame
 var first=await shot(g,Vector3(-25,0,24),"expedition-start","EXPEDITION: actual new mission start")
 # The following view is a controlled inspection fixture, not natural play evidence.
 var scout=g._first(0,"scout");scout.pos=g.FrontierExpedition.OUTPOST+Vector3(-5,0,0)
 var second=await shot(g,g.FrontierExpedition.OUTPOST,"expedition-outpost-fixture","CONTROLLED SCOUT VIEW: not a completed mission")
 print("EXPEDITION_CAPTURE: ","SKIPPED_NO_DISPLAY" if DisplayServer.get_name()=="headless" else "native frames saved; second frame is controlled scouting fixture")
 print(JSON.stringify({"build":g.Rules.BUILD_ID,"stage":g.frontier_expedition.stage,"rendered":DisplayServer.get_name()!="headless","first_error":first,"second_error":second,"scope":"Actual newly started mission, then controlled repositioned scout reveal; no natural mission completion or physical phone claim."}));g.queue_free();quit(0 if first==OK and second==OK else 1)
