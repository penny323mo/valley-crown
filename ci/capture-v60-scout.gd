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
 g.paused=false;g.application_focused=true;g.application_suspended=false;g._skip_tutorial();g.camera_zoom=18
 var scout=g._first(0,"scout");g._set_stance(scout,"STOP");g._update_vision(false);g._publish_faction_views();g._select([scout.id]);g.camera_focus=scout.pos
 g.compact_menu.show();g.compact_menu_dismiss.show();g._set_shortcut_category("army");g._refresh_idle_dispatch_buttons();g._layout_ui()
 await process_frame
 g.shortcut_scroll.ensure_control_visible(g.scout_dispatch_button)
 var ok=await shot(g,"native-army-idle-scout-exploration-action")
 var before=g.explored_cells[0].count(1);var origin=scout.pos;g._dispatch_player_scout();var queued=g.commands.size()
 if queued!=1:print("NO_SCOUT_ORDER");g.queue_free();quit(1);return
 var goal=g.commands[0].position;var tick=0
 ok=(await shot(g,"native-scout-before-unexplored-leg")) and ok
 for i in 500:
  g._tick(.05);tick+=1
  if scout.state=="idle" and scout.pos.distance_to(origin)>1:break
 g.camera_focus=scout.pos
 ok=(await shot(g,"native-scout-arrived-new-ground-revealed")) and ok
 var proof={"build":g.Rules.BUILD_ID,"queued":queued,"origin":[origin.x,origin.z],"goal":[goal.x,goal.z],"final_position":[scout.pos.x,scout.pos.z],"explored_before":before,"explored_after":g.explored_cells[0].count(1),"idle_on_arrival":scout.state=="idle","no_requeue":g.commands.is_empty(),"ticks":tick,"rendered":DisplayServer.get_name()!="headless","scope":"Controlled idle starting scout; actual Army menu callback, ordinary ground movement and vision. No hidden enemy/terrain lookup, saved files or phone acceptance. Single requested destination, not automatic whole-map exploration."}
 print(JSON.stringify(proof));g.queue_free();quit(0 if ok and scout.pos.distance_to(origin)>1 and proof.explored_after>before and proof.idle_on_arrival and proof.no_requeue else 1)
