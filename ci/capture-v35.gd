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
 var home=g._first(1,"town_center");var building=g._spawn("tower",1,home.pos+Vector3(-8,0,-1));building.hp=300;building.last_damage_tick=-1000
 var workers=[]
 for w in g.entities:
  if w.team==1 and w.kind=="villager":workers.append(w)
 for i in 2:g._order(workers[i],"gather",g._nearest_resource(workers[i].pos,"food",1).id)
 workers[2].pos=building.pos+Vector3(-2,0,0);g._set_stance(workers[2],"STOP")
 g._navigation_rebuild();g._update_vision(false);g._publish_faction_views();g.ai_opening_assigned=true;g._ai_update()
 var commands=g.commands.filter(func(c):return c.type=="order" and c.target==building.id)
 if commands.size()!=1:print("NO_REPAIR");g.queue_free();quit(1);return
 # Isolate one real paid repair from unrelated queued training/construction.
 g.commands=commands.duplicate(true)
 var bank=g.economy.bank_milli(1).wood
 var observer=g._first(0,"scout");var original=observer.pos
 observer.pos=building.pos+Vector3(-7,0,0);g._set_stance(observer,"STOP");g.camera_focus=building.pos;g._update_vision(false);g._publish_faction_views();g._select([building.id])
 var ok=await shot(g,"native-ai-damaged-tower-repair-requested")
 observer.pos=original;g._update_vision(false);g._publish_faction_views()
 var ticks=0
 for i in 1000:
  g._tick(.05);ticks+=1
  if building.hp>=340:break
 var paid=g.economy.bank_milli(1).wood<bank
 observer.pos=building.pos+Vector3(-7,0,0);g._update_vision(false);g._publish_faction_views();g._select([building.id])
 ok=(await shot(g,"native-ai-tower-real-paid-restoration")) and ok
 var proof={"build":g.Rules.BUILD_ID,"ordinary_repair_queued":commands.size()==1,"initial_hp":300,"final_hp":building.hp,"wood_before":bank,"wood_after":g.economy.bank_milli(1).wood,"paid":paid,"ticks":ticks,"ledger_conserved":g.economy.audit().ok,"rendered":DisplayServer.get_name()!="headless","scope":"Controlled damaged AI tower, real full AI planning and ordinary worker paid repair. Other queued actions isolated. Player scout positioned only for stills then removed before work, no fog override. No saves/natural-match or phone acceptance."}
 print(JSON.stringify(proof));g.queue_free();quit(0 if ok and paid and building.hp>=340 and proof.ledger_conserved else 1)
