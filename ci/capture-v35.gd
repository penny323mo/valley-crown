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
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false)
 await process_frame
 g.paused=false;g.application_focused=true;g.application_suspended=false;g._skip_tutorial()
 var workers=[]
 for e in g.entities:
  if e.team==0 and e.kind=="villager":workers.append(e)
 workers.sort_custom(func(a,b):return a.id<b.id)
 var positions=[Vector3(20.5,0,20.5),Vector3(-3.5,0,7.5),Vector3(0.5,0,7.5),Vector3(4.5,0,7.5),Vector3(23.5,0,23.5)]
 for i in workers.size():workers[i].pos=positions[i];g._set_stance(workers[i],"STOP")
 var nodes=[]
 for p in [Vector3(-3.5,0,4.5),Vector3(0.5,0,4.5),Vector3(4.5,0,4.5)]:nodes.append(g._spawn("pine",-1,p))
 var depot=g._spawn("storehouse",0,Vector3(0.5,0,11.5),true)
 g._navigation_rebuild();g._update_vision(false);g._publish_faction_views()
 g.camera_focus=Vector3(0.5,0,7.5);g.camera_zoom=18;g._camera_update()
 var expected=[workers[1].id,workers[2].id,workers[3].id]
 g._select(expected);g.compact_menu.show();g._set_shortcut_category("economy");g._refresh_idle_dispatch_buttons()
 var planned=g.IdleGatherDispatch.orders(g.faction_views[0].records(),g.commands,"wood")
 var before=g.economy.bank_milli(0).wood
 var ok=await shot(g,"native-quick-gather-economy-menu")
 g._dispatch_idle_gather("wood")
 var chosen=[];var targets=[];var starts={};var node_before={}
 for c in g.commands:
  if c.get("idle_gather","")=="wood":chosen.append(c.ids[0]);targets.append(c.target);starts[c.ids[0]]=g._get_entity(c.ids[0]).pos;node_before[c.target]=g.economy.node_view(c.target).remaining_milli
 var picked=chosen.duplicate();picked.sort();expected.sort()
 var nearest=picked==expected;var distinct={}
 for t in targets:distinct[t]=true
 var distributed=distinct.size()==3
 for i in 30:g._tick(.05)
 var moved=true
 for id in chosen:moved=moved and g._get_entity(id).pos.distance_to(starts[id])>0.1
 ok=(await shot(g,"native-nearby-workers-walk-to-three-trees")) and ok
 var harvested=false;var deposited=false;var elapsed=30
 for i in 1800:
  g._tick(.05);elapsed+=1
  if not harvested:
   harvested=not targets.is_empty()
   for id in targets:harvested=harvested and g.economy.node_view(id).remaining_milli<node_before[id]
   if harvested:ok=(await shot(g,"native-three-workers-harvest-separate-trees")) and ok
  if g.economy.bank_milli(0).wood>before:deposited=true;break
  if i%100==0:await process_frame
 var cargo=[]
 for id in chosen:cargo.append({"id":id,"cargo_milli":g._cargo_amount(g._get_entity(id)),"state":g._get_entity(id).state})
 ok=(await shot(g,"native-harvest-return-increases-real-wood")) and ok
 var proof={"build":g.Rules.BUILD_ID,"scope":"Controlled own worker positions, three spawned resource nodes and completed dropoff; actual quick dispatch, ordinary paths, harvest and deposit. No saves, natural-match, phone or benchmark acceptance.","planned":planned,"chosen":chosen,"targets":targets,"nearest_three":nearest,"three_distinct_targets":distributed,"actual_movement":moved,"all_targets_harvested":harvested,"real_deposit":deposited,"wood_before_milli":before,"wood_after_milli":g.economy.bank_milli(0).wood,"cargo":cargo,"ticks":elapsed,"ledger_conserved":g.economy.audit().ok,"rendered":DisplayServer.get_name()!="headless"}
 print(JSON.stringify(proof))
 g.queue_free();quit(0 if ok and nearest and distributed and moved and harvested and deposited and proof.ledger_conserved else 1)
