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
 root.size=Vector2i(960,540)
 DirAccess.make_dir_recursive_absolute("/tmp/capture")
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="expedition";root.add_child(g)
 g.test_mode=true;g.set_process(false);await process_frame
 await shot(g,Vector3(-25,0,24),"expedition-start","前線遠征：實際初始狀態，尚未完成任何目標")
 # The following view is a controlled inspection fixture, not natural play evidence.
 var scout=g._first(0,"scout");scout.pos=g.FrontierExpedition.OUTPOST+Vector3(-5,0,0)
 await shot(g,g.FrontierExpedition.OUTPOST,"expedition-outpost-fixture","受控展示：偵察兵移到哨站附近，非自然通關截圖")
 print("EXPEDITION_CAPTURE: ","SKIPPED_NO_DISPLAY" if DisplayServer.get_name()=="headless" else "native frames saved; second frame is controlled scouting fixture")
 quit()
