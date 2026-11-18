extends SceneTree
# UNRUN: fresh ordinary opening, paid placement and normal ticks; no authority setup.
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
const Reassign=preload("res://scripts/workforce_reassign.gd")
var g
var rows=[]
var checks=[]
func check(name,ok):
 checks.append({"name":name,"passed":bool(ok)})
 if not ok:push_error(name)
func strict_roundtrip(label):
 var capture=Codec.capture_result(g)
 var encoded=Codec.encode(capture.data,g.Rules.BUILD_ID) if capture.ok else {"ok":false}
 var decoded=Codec.decode(encoded.bytes,g.Rules.BUILD_ID) if encoded.ok else {"ok":false}
 check(label+" exact build codec accepts",capture.ok and encoded.ok and decoded.ok)
 if not decoded.ok:print("ROUNDTRIP_FAILURE "+str(capture));return
 var clone=load("res://main.tscn").instantiate();clone.skirmish_mode="practice";root.add_child(clone);clone.set_process(false);clone.test_mode=true
 var restored=Restore.apply(clone,decoded.data)
 if restored:clone._toggle_pause()
 var after=Codec.capture_result(clone)
 check(label+" restore preserves full authority",restored and after.ok and after.data==capture.data)
 clone.free()
func pure_checks():
 var w={"id":1,"owned":true,"alive":true,"remembered":false,"team":0,"category":"unit","kind":"villager","state":"gather","gather_type":"wood","resource_target":7,"work_epoch":3,"pos":Vector3.ZERO,"cargo_milli":2000}
 var f={"id":10,"owned":true,"alive":true,"remembered":false,"team":0,"category":"building","kind":"farm","built":true,"pos":Vector3(2,0,0)}
 var records={1:w,10:f};var ledger={10:-1};var original=records.duplicate(true)
 var plan=Reassign.orders(records,[1],[],"food",ledger)
 check("loaded selected miner can plan vacant farm with ordinary marker",plan.size()==1 and plan[0].farm_gather and plan[0].source_work_epoch==3)
 check("unknown occupancy fails closed",Reassign.orders(records,[1],[],"food").is_empty())
 check("occupied farm excluded",Reassign.orders(records,[1],[],"food",{10:2}).is_empty())
 check("pending farm destination reserved",Reassign.orders(records,[1],[{"team":0,"type":"order","ids":[2],"target":10}],"food",ledger).is_empty())
 check("pending worker construction preserved",Reassign.orders(records,[1],[{"team":0,"type":"build","builder":1}],"food",ledger).is_empty())
 for key in ["alive","built","owned","remembered","team"]:
  var bad=f.duplicate();bad[key]=true if key=="remembered" else 1 if key=="team" else false
  check("farm rejects "+key,Reassign.orders({1:w,10:bad},[1],[],"food",ledger).is_empty())
 var other=w.duplicate();other.id=2;other.state="deliver";other.resource_target=10
 check("loaded pending farmer reserves field before ledger claim",Reassign.orders({1:w,2:other,10:f},[1],[],"food",ledger).is_empty())
 var enemy={"id":20,"alive":true,"remembered":false,"team":1,"category":"unit","pos":Vector3.ONE}
 check("currently observed threat excludes farm",Reassign.orders({1:w,10:f,20:enemy},[1],[],"food",ledger).is_empty())
 enemy.remembered=true
 check("remembered enemy not hidden threat oracle",Reassign.orders({1:w,10:f,20:enemy},[1],[],"food",ledger).size()==1)
 var w2=w.duplicate();w2.id=2;var w3=w.duplicate();w3.id=3
 var f2=f.duplicate();f2.id=11;f2.pos=Vector3(3,0,0)
 var batch=Reassign.orders({1:w,2:w2,3:w3,10:f,11:f2},[1,2,3],[],"food",{10:-1,11:-1})
 check("three miners two fields assign distinct farmers once",batch.size()==2 and batch[0].target!=batch[1].target and batch[0].ids!=batch[1].ids)
 var berry={"id":12,"category":"resource","kind":"berry","alive":true,"remembered":false,"hp":100,"pos":Vector3(4,0,0)}
 batch=Reassign.orders({1:w,2:w2,3:w3,10:f,11:f2,12:berry},[1,2,3],[],"food",{10:-1,11:-1})
 check("surplus worker may still use ordinary berries",batch.size()==3 and batch.map(func(o):return o.target).has(12))
 check("farm never becomes wood target",Reassign.orders(records,[1],[],"iron",ledger).is_empty())
 var idle=w.duplicate();idle.state="idle";idle.cargo_milli=0;idle.path=[];idle.path_pending=false
 var dispatch=load("res://scripts/idle_gather_dispatch.gd")
 check("empty idle worker food dispatch includes vacant farm",dispatch.orders({1:idle,10:f},[],"food",ledger).size()==1)
 idle.cargo_milli=1
 check("idle dispatch still refuses loaded worker",dispatch.orders({1:idle,10:f},[],"food",ledger).is_empty())
 check("planning does not mutate records or ledger",records==original and ledger=={10:-1})

func _initialize():call_deferred("run")
func note(name,value):
 rows.append({"name":name,"value":value,"tick":g.tick_count});print("DIAGNOSTIC "+JSON.stringify(rows[-1]))
func advance(count):
 for i in count:
  if g.game_over:break
  g._tick(g.Rules.TICK)
func run():
 pure_checks()
 root.size=Vector2i(640,360)
 g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";root.add_child(g);g.set_process(false);g.test_mode=true
 await process_frame
 note("opening",{"build":g.Rules.BUILD_ID,"mode":g.skirmish_mode,"bank":g.economy.bank_milli(0),"ai":g.ai_enabled})
 var worker=g._first(0,"villager")
 var woods=g.faction_views[0].records().values().filter(func(r):return r.get("alive",false) and not r.get("remembered",true) and r.get("kind","") in ["pine","oak"])
 woods.sort_custom(func(a,b):return worker.pos.distance_squared_to(a.pos)<worker.pos.distance_squared_to(b.pos))
 if woods.is_empty():quit(1);return
 var wood=woods[0]
 var p=Vector3.INF;var best=INF
 for y in g.Rules.MAP_SIZE:
  for x in g.Rules.MAP_SIZE:
   var q=g._point(Vector2i(x,y));var d=q.distance_squared_to(wood.pos)
   if d<best and g._placement_reason("farm",q,0,worker.id).is_empty():best=d;p=q
 if not p.is_finite():push_error("no legal observed farm placement");quit(1);return
 var bank=g.economy.bank_milli(0).duplicate(true)
 g._select([worker.id]);g._start_build("farm");g.pointer_world=p;g.build_preview_held=true;g._update_ghost()
 if not g.placement_ok:push_error("ordinary placement rejected");quit(1);return
 g._confirm_build();advance(1)
 var farm={}
 for e in g.entities:
  if e.alive and e.team==0 and e.kind=="farm":farm=e
 if farm.is_empty():push_error("normal paid build produced no site");quit(1);return
 check("ordinary construction costs exactly sixty wood",bank.wood-g.economy.bank_milli(0).wood==60000)
 note("paid_site",{"id":farm.id,"before":bank,"after":g.economy.bank_milli(0),"receipt":farm.get("cost_receipt_id",-1)})
 for i in 1500:
  if farm.built:break
  advance(1)
 if not farm.built:push_error("ordinary construction did not finish within bound");quit(1);return
 check("ordinary paid farm completes and automatically farms",worker.state=="gather" and worker.target==farm.id)
 note("completed_autofarming",{"worker_state":worker.state,"target":worker.target,"farm":g.economy.farm_view(farm.id)})
 var resources=g.faction_views[0].records().values().filter(func(r):return r.get("alive",false) and not r.get("remembered",true) and r.get("kind","") in ["iron","stone","pine","oak"])
 resources.sort_custom(func(a,b):return worker.pos.distance_squared_to(a.pos)<worker.pos.distance_squared_to(b.pos))
 if resources.is_empty():push_error("no currently observed nonfood resource");quit(1);return
 var second=g.entities.filter(func(e):return e.alive and e.team==0 and e.kind=="villager" and e.id!=worker.id)[0]
 var target=wood
 g._submit("order",{"ids":[second.id],"target":target.id,"position":target.pos})
 g._submit("order",{"ids":[worker.id],"target":target.id,"position":target.pos});advance(1)
 for i in 1000:
  if g.economy.worker_view(worker.id).get("cargo_milli",0)>0 and worker.gather_type!="food" and g.economy.worker_view(second.id).get("cargo_milli",0)>0:break
  advance(1)
 check("both workers earn real wood and farm is vacant",g.economy.worker_view(worker.id).cargo_milli>0 and g.economy.worker_view(second.id).cargo_milli>0 and g.economy.farm_view(farm.id).worker_id==-1)
 note("worker_resource_work",{"state":worker.state,"type":worker.gather_type,"ledger":g.economy.worker_view(worker.id),"farm":g.economy.farm_view(farm.id)})
 g._select([worker.id]);g._update_hud()
 var records=g.faction_views[0].records()
 var plans=Reassign.orders(records,[worker.id],g.commands,"food",g._food_dispatch_farm_workers())
 check("actual current observation food plan chooses nearby paid farm",plans.size()==1 and plans[0].target==farm.id)
 note("actual_food_shortcut",{"plans":plans,"farm_record":records.get(farm.id,{}),"visible_berries":records.values().filter(func(r):return r.get("kind","")=="berry" and not r.get("remembered",true))})
 # Pure policy boundary only: not written back into faction view/game.
 var farm_only=records.duplicate(true)
 for id in farm_only.keys():
  if farm_only[id].get("category","")=="resource":farm_only.erase(id)
 note("controlled_policy_farm_only",Reassign.orders(farm_only,[worker.id],g.commands,"food",g._food_dispatch_farm_workers()))
 # Manual legal world-tap workaround, camera change is presentation only.
 g.camera_focus=farm.pos;g._camera_update();g._update_hud();await process_frame
 var screen=g.camera.unproject_position(farm.pos)
 note("manual_pick",{"screen":str(screen),"picked":g._pick(screen,false)})
 var food_before=g.economy.bank_milli(0).food
 g.compact_menu.show();g._refresh_idle_dispatch_buttons()
 note("shortcut_metadata",g.workforce_reassign_buttons.food.get_meta("squad_ids",[]))
 for size in [Vector2i(320,568),Vector2i(390,844),Vector2i(640,360)]:
  root.size=size;g._layout_ui();await process_frame;await process_frame
  var b=g.workforce_reassign_buttons.food
  check("food reassign target remains reachable "+str(size),b.size.x>=140 and b.get_global_rect().position.x>=g.shortcut_scroll.get_global_rect().position.x and b.get_global_rect().end.x<=g.shortcut_scroll.get_global_rect().end.x)
 g.paused=true;g._refresh_idle_dispatch_buttons();g._reassign_selected_workforce("food")
 check("pause cannot submit food shortcut",g.commands.is_empty())
 g.paused=false;g._refresh_idle_dispatch_buttons()
 var held=g.selected.duplicate();g.selected=[];g._reassign_selected_workforce("food")
 check("changed held selection cannot submit",g.commands.is_empty())
 g.selected=held;g._refresh_idle_dispatch_buttons();g._set_shortcut_category("economy")
 g.compact_menu.show();g._layout_ui();await process_frame;await process_frame
 var food_button=g.workforce_reassign_buttons.food
 g.shortcut_scroll.ensure_control_visible(food_button);await process_frame;await process_frame
 var button_point=food_button.get_global_rect().get_center()
 check("food shortcut root touch point visible inside scroll",food_button.is_visible_in_tree() and g.shortcut_scroll.get_global_rect().has_point(button_point))
 var touch=InputEventScreenTouch.new();touch.index=0;touch.position=button_point;touch.pressed=true;root.push_input(touch)
 touch=InputEventScreenTouch.new();touch.index=0;touch.position=button_point;touch.pressed=false;root.push_input(touch)
 check("controller submits one marked ordinary farm order",g.commands.size()==1 and g.commands[0].get("farm_gather",false) and g.commands[0].get("work_reassign","")=="food")
 if g.commands.size()!=1:quit(1);return
 strict_roundtrip("pending farm shortcut")
 var original_order=g.commands.pop_front();var cargo=g.economy.worker_view(worker.id).cargo_milli
 g._execute(original_order)
 check("accepted loaded worker preserves cargo before normal delivery",g.economy.worker_view(worker.id).cargo_milli==cargo and worker.state=="deliver" and worker.resource_target==farm.id and g.economy.farm_view(farm.id).worker_id==-1)
 strict_roundtrip("cargo delivery awaiting farm claim")
 var second_before=var_to_bytes(second.duplicate(true));var second_cargo=g.economy.worker_view(second.id).duplicate(true)
 var competing=original_order.duplicate(true);competing.ids=[second.id];competing.source_work_epoch=second.work_epoch;competing.source_resource=second.gather_type
 competing.erase("command_id");g._submit("order",competing);competing=g.commands.pop_front()
 check("competing worker receives distinct ordinary command identity",competing.command_id!=original_order.command_id)
 g._execute(competing)
 check("same tick second loaded farmer rejected atomically",var_to_bytes(second)==second_before and g.economy.worker_view(second.id)==second_cargo)
 var epoch=worker.work_epoch;g._execute(original_order)
 check("duplicate command cannot reset work",worker.work_epoch==epoch)
 var stale=original_order.duplicate(true);stale.erase("command_id");g._submit("order",stale);stale=g.commands.pop_front()
 var stale_before=var_to_bytes(worker.duplicate(true));var stale_cargo=g.economy.worker_view(worker.id).duplicate(true)
 check("stale epoch command has a fresh identity",stale.command_id!=original_order.command_id and stale.source_work_epoch!=worker.work_epoch)
 g._execute(stale)
 check("fresh identity stale epoch rejected atomically",var_to_bytes(worker)==stale_before and g.economy.worker_view(worker.id)==stale_cargo)

 note("manual_commands",g.commands.duplicate(true))
 for i in 2000:
  advance(1)
  if g.economy.bank_milli(0).food>food_before:break
 check("shortcut farmer physically generates and deposits ten food",g.economy.bank_milli(0).food>=food_before+10000 and g.economy.farm_view(farm.id).generated_milli>=10000)
 check("normal ledger remains conserved",g.economy.audit().ok)
 note("manual_result",{"worker":g.economy.worker_view(worker.id),"farm":g.economy.farm_view(farm.id),"food_before":food_before,"food_after":g.economy.bank_milli(0).food,"audit":g.economy.audit()})
 print("DIAGNOSTIC "+JSON.stringify({"scope":"ordinary paid farm and work; isolated farm-only policy fixture is not natural observation; manual root touch workaround","rows":rows}))
 g._submit("stop",{"ids":[worker.id]});advance(1)
 check("normal stop releases a genuinely empty farmer",g.economy.farm_view(farm.id).worker_id==-1 and g.economy.worker_view(worker.id).cargo_milli==0)
 g.compact_menu.show();g._refresh_idle_dispatch_buttons()
 var idle_plan=load("res://scripts/idle_gather_dispatch.gd").orders(g.faction_views[0].records(),g.commands,"food",g._food_dispatch_farm_workers())
 check("actual idle food plan includes nearby vacant paid field",idle_plan.any(func(o):return o.target==farm.id))
 g._dispatch_idle_gather("food");advance(1)
 check("idle shortcut actually assigns one farmer without extra payment",g.economy.farm_view(farm.id).worker_id>=0 and g.economy.farm_view(farm.id).worker_id==worker.id)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"food_farm_shortcut_contract","checks":checks,"failed":failed,"scope":"Pure observed-policy negatives plus fresh practice paid farm, real wood cargo, normal controller transfer and food delivery; no phone claim"}))
 g.queue_free();quit(1 if failed else 0)
