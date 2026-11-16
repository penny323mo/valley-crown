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
 g.paused=false;g.application_focused=true;g.application_suspended=false;g._skip_tutorial();g.camera_zoom=15
 var home=g._first(1,"town_center");var soldier=g._spawn("spearman",1,home.pos+Vector3(-10,0,0));soldier.hp=10
 var observer=g._first(0,"scout");var original=observer.pos
 g._navigation_rebuild();g._update_vision(false);g._publish_faction_views()
 g.ai_raid_members=[soldier.id];g.ai_raid_departure_count=1;g._ai_army(g._ai_records(),home)
 var queued=g.commands.any(func(c):return c.type=="order" and soldier.id in c.get("ids",[]) and c.target==-1)
 g._tick(.05)
 # Observe only between simulated phases. Remove observer before healing ticks,
 # so actual normal threat-aware rest (not forced HP changes) does the healing.
 observer.pos=soldier.pos+Vector3(-7,0,0);g._set_stance(observer,"STOP");g.camera_focus=home.pos+Vector3(-5,0,0);g._update_vision(false);g._publish_faction_views();g._select([soldier.id])
 var ok=await shot(g,"native-ai-wounded-troop-withdrawing")
 observer.pos=original;g._update_vision(false);g._publish_faction_views()
 var ticks=1;var arrived=false
 for i in 1200:
  g._tick(.05);ticks+=1
  if i%20==0:g._ai_army(g._ai_records(),home)
  if soldier.state=="idle" and soldier.pos.distance_to(home.pos)<=7:arrived=true;break
 var arrival_hp=soldier.hp
 for i in 320:
  g._tick(.05);ticks+=1
  if i%20==0:g._ai_army(g._ai_records(),home)
 var early_hp=soldier.hp
 observer.pos=soldier.pos+Vector3(-7,0,0);g._update_vision(false);g._publish_faction_views();g._select([soldier.id])
 ok=(await shot(g,"native-ai-reserve-ordinary-healing")) and ok
 observer.pos=original;g._update_vision(false);g._publish_faction_views()
 var threshold=ceili(soldier.max_hp*.8)
 for i in 5000:
  g._tick(.05);ticks+=1
  if i%20==0:g._ai_army(g._ai_records(),home)
  if soldier.hp>=threshold:break
 var ready=soldier.hp>=threshold
 observer.pos=soldier.pos+Vector3(-7,0,0);g._update_vision(false);g._publish_faction_views();g._select([soldier.id])
 ok=(await shot(g,"native-ai-recovered-troop-ready")) and ok
 var proof={"build":g.Rules.BUILD_ID,"ordinary_home_order":queued,"physically_arrived":arrived,"arrival_hp":arrival_hp,"early_healed_hp":early_hp,"final_hp":soldier.hp,"max_hp":soldier.max_hp,"ready":ready,"ticks":ticks,"rendered":DisplayServer.get_name()!="headless","scope":"Controlled damaged enemy soldier; real ordinary AI return and timed healing. Player scout positioned for each still then removed before simulation, because normal enemy proximity blocks recovery. No saves, natural-match or phone acceptance."}
 print(JSON.stringify(proof));g.queue_free();quit(0 if ok and queued and arrived and early_hp>arrival_hp and ready else 1)
