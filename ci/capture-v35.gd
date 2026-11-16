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
 g.paused=false;g.application_focused=true;g.application_suspended=false;g._skip_tutorial();g.camera_zoom=17
 var workers=[]
 for e in g.entities:
  if e.team==1 and e.kind=="villager":workers.append(e)
 var pine1=g._spawn("pine",-1,Vector3(7.5,0,-7.5));var pine2=g._spawn("pine",-1,Vector3(9.5,0,-7.5))
 for i in 2:g._order(workers[i],"gather",g._nearest_resource(workers[i].pos,"food",1).id)
 workers[2].pos=Vector3(7.5,0,-10.5);workers[3].pos=Vector3(9.5,0,-10.5);workers[4].pos=Vector3(10.5,0,-10.5)
 g._order(workers[2],"gather",pine1.id);g._order(workers[3],"gather",pine2.id);g._set_stance(workers[4],"STOP")
 g._first(1,"scout").pos=Vector3(9.5,0,-5.5);g._navigation_rebuild();g._update_vision(false);g._publish_faction_views()
 var bank=g.economy.bank_milli(1).wood;g.ai_opening_assigned=true;g._ai_update()
 var builds=g.commands.filter(func(c):return c.type=="build" and c.kind=="storehouse")
 if builds.size()!=1:print("NO_OUTPOST_COMMAND");g.queue_free();quit(1);return
 var command=builds[0];g.commands.erase(command);g._execute(command)
 var site=g._first(1,"storehouse")
 if site.is_empty():print("NO_PAID_SITE");g.queue_free();quit(1);return
 var paid=g.economy.bank_milli(1).wood==bank-80000
 # Controlled player scout reveals the already-chosen enemy site; never grants fog vision.
 var observer=g._first(0,"scout");observer.pos=site.pos+Vector3(7,0,0);g._set_stance(observer,"STOP")
 g.camera_focus=site.pos;g._update_vision(false);g._publish_faction_views();g._select([site.id])
 var ok=await shot(g,"native-ai-paid-remote-storehouse-construction")
 var ticks=0
 for i in 2000:
  g._tick(.05);ticks+=1
  if site.built:break
 ok=(await shot(g,"native-ai-completed-resource-outpost")) and ok
 var delivered=false;var tracked=-1
 for i in 2400:
  for w in [workers[2],workers[3]]:
   if w.state=="deliver" and w.target==site.id and g._cargo_amount(w)>0:tracked=w.id
  var cargo=g._cargo_amount(g._get_entity(tracked)) if tracked>=0 else 0
  var wood=g.economy.bank_milli(1).wood
  g._tick(.05);ticks+=1
  if tracked>=0 and cargo>0 and g._cargo_amount(g._get_entity(tracked))==0 and g.economy.bank_milli(1).wood>wood:delivered=true;break
 ok=(await shot(g,"native-ai-miner-delivers-to-new-outpost")) and ok
 var proof={"build":g.Rules.BUILD_ID,"scope":"Controlled AI gathering cluster and player scout observation; full ordinary AI planning turn, paid construction and physical miner deposit. No saved files, natural-match balance or phone acceptance.","ordinary_build_queued":builds.size()==1,"eighty_wood_paid":paid,"completed":site.built,"miner_used_new_dropoff":tracked>=0,"real_deposit":delivered,"ledger_conserved":g.economy.audit().ok,"ticks":ticks,"rendered":DisplayServer.get_name()!="headless"}
 print(JSON.stringify(proof));g.queue_free();quit(0 if ok and paid and site.built and delivered and proof.ledger_conserved else 1)
