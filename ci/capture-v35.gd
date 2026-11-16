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
 g.paused=false;g.application_focused=true;g.application_suspended=false;g._skip_tutorial();g.camera_zoom=18;g.camera_focus=Vector3.ZERO;g.commands.clear()
 var workers=[]
 for e in g.entities:
  if e.alive and e.team==1 and e.kind=="villager" and workers.size()<3:workers.append(e)
 for i in workers.size():workers[i].pos=Vector3(i-1,0,0);g._set_stance(workers[i],"STOP")
 var a=g._spawn("pine",-1,Vector3(-1.5,0,3.5));var b=g._spawn("pine",-1,Vector3(1.5,0,3.5));g._spawn("storehouse",1,Vector3(0,0,-5),true)
 var observer=g._first(0,"scout");observer.pos=Vector3(7,0,0);g._set_stance(observer,"STOP")
 g._update_vision(false);g._publish_faction_views()
 var before=g.economy.bank_milli(1).wood;var assignments=[];var targets={}
 for w in workers:g._assign_worker(g.faction_views[1].get_record(w.id),"wood")
 for c in g.commands:assignments.append({"worker":c.ids[0],"node":c.target});targets[c.target]=true
 var ok=await shot(g,"native-ai-local-resource-split-before")
 var elapsed=0
 for i in 1400:
  g._tick(.05);elapsed+=1
  if g.economy.bank_milli(1).wood>before:break
 ok=(await shot(g,"native-ai-split-harvest-and-paid-in-wood")) and ok
 var proof={"build":g.Rules.BUILD_ID,"assignments":assignments,"two_local_nodes":targets.has(a.id) and targets.has(b.id),"bank_wood_before_milli":before,"bank_wood_after_milli":g.economy.bank_milli(1).wood,"ticks":elapsed,"ledger_ok":g.economy.audit().ok,"rendered":DisplayServer.get_name()!="headless","scope":"Controlled three AI workers, two resource nodes and preplaced depot; actual _assign_worker, normal movement/harvest/deposit. Player scout supplies normal visible observation. No saved files, no throughput or physical-phone claim."}
 print(JSON.stringify(proof));g.queue_free();quit(0 if ok and proof.two_local_nodes and proof.bank_wood_after_milli>before and proof.ledger_ok else 1)
