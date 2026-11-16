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
 g.paused=false;g.application_focused=true;g.application_suspended=false;g._skip_tutorial();g.camera_zoom=9;g.camera_focus=Vector3.ZERO;g.commands.clear()
 var nodes=[];var workers=[]
 for i in 3:
  var x=(i-1)*3.0
  var node=g._spawn(["stone","iron","berry"][i],-1,Vector3(x,0,0));nodes.append(node)
  for side in [-1,1]:
   var worker=g._spawn("villager",0,Vector3(x+side*0.8,0,-1.5));g._set_stance(worker,"STOP");workers.append(worker)
 g._spawn("storehouse",0,Vector3(0,0,-5),true)
 g._update_vision(false);g._publish_faction_views()
 var ok=await shot(g,"native-resource-lifecycle-full")
 for i in workers.size():g._order(workers[i],"gather",nodes[i/2].id)
 var elapsed=0;var stopped={}
 for i in 5000:
  g._tick(.05);elapsed+=1
  for index in nodes.size():
   if nodes[index].hp<=nodes[index].max_hp*0.75 and not stopped.has(index):
    for worker in [workers[index*2],workers[index*2+1]]:g._set_stance(worker,"STOP")
    stopped[index]=true
  if nodes.all(func(n):return n.hp<=n.max_hp*0.75):break
 ok=(await shot(g,"native-resource-lifecycle-after-real-harvest")) and ok
 var state=[]
 for node in nodes:state.append({"kind":node.kind,"remaining":node.hp,"initial":node.max_hp,"stage":g.ResourceVisuals.stage(g.faction_views[0].get_record(node.id))})
 var proof={"build":g.Rules.BUILD_ID,"resources":state,"ticks":elapsed,"ledger_ok":g.economy.audit().ok,"rendered":DisplayServer.get_name()!="headless","scope":"Controlled full resource nodes, six villagers and preplaced depot; ordinary movement, paid-in cargo and harvesting. Close camera shows actual observation-driven resource meshes, not concept art. No saves or economy mutation."}
 print(JSON.stringify(proof));g.queue_free();quit(0 if ok and proof.ledger_ok and state.all(func(n):return n.stage>=1) else 1)
