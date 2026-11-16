extends SceneTree
const Policy=preload("res://scripts/workforce_reassign.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var w={"id":1,"owned":true,"alive":true,"team":0,"category":"unit","kind":"villager","state":"gather","gather_type":"food","work_epoch":3,"pos":Vector3.ZERO,"cargo_milli":2000}
 var n={"id":10,"category":"resource","kind":"pine","alive":true,"remembered":false,"hp":100,"pos":Vector3(3,0,0)}
 var records={1:w,10:n};var original=records.duplicate(true)
 var plan=Policy.orders(records,[1],[],"wood")
 check("selected active gatherer planned with epoch",plan.size()==1 and plan[0].source_work_epoch==3 and plan[0].source_resource=="food")
 check("carried cargo allowed without mutation",records==original)
 check("unselected never commandeered",Policy.orders(records,[],[],"wood").is_empty())
 check("same resource not interrupted",Policy.orders(records,[1],[],"food").is_empty())
 check("unavailable resource disabled",Policy.orders(records,[1],[],"iron").is_empty())
 check("pending new order preserved",Policy.orders(records,[1],[{"team":0,"type":"order","ids":[1]}],"wood").is_empty())
 check("pending building preserved",Policy.orders(records,[1],[{"team":0,"type":"build","builder":1}],"wood").is_empty())
 for state in ["idle","build","repair","attack","move"]:
  var c=w.duplicate();c.state=state;check("exclude "+state,Policy.orders({1:c,10:n},[1],[],"wood").is_empty())
 var delivering=w.duplicate();delivering.state="deliver"
 check("delivery may switch without dropping cargo",Policy.orders({1:delivering,10:n},[1],[],"wood").size()==1)
 for key in ["remembered","alive","hp"]:
  var c=n.duplicate();c[key]=true if key=="remembered" else false if key=="alive" else 0
  check("invalid node "+key,Policy.orders({1:w,10:c},[1],[],"wood").is_empty())
 var enemy={"id":20,"alive":true,"team":1,"category":"unit","pos":Vector3.ONE}
 check("known threat rejects transfer",Policy.orders({1:w,10:n,20:enemy},[1],[],"wood").is_empty())
 var ids=[1]
 for i in range(2,6):var c=w.duplicate();c.id=i;records[i]=c;ids.append(i)
 check("batch remains capped at three",Policy.orders(records,ids,[],"wood").size()==3)
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.set_process(false);g.ai_enabled=false;await process_frame
 g.paused=false;g.application_focused=true;g.application_suspended=false
 var worker=g._first(0,"villager");var berry=g._nearest_resource(worker.pos,"food",0)
 g._order(worker,"gather",berry.id)
 for i in 1800:
  g._tick(.05)
  if g._cargo_amount(worker)>0:break
 check("fixture earns actual food cargo",g._cargo_amount(worker)>0 and g._cargo_type(worker)=="food")
 g._update_vision(false);g._publish_faction_views();g._select([worker.id]);g.compact_menu.show();g._refresh_idle_dispatch_buttons()
 check("owned view exposes work epoch",g.faction_views[0].records()[worker.id].work_epoch==worker.work_epoch)
 var candidate=Policy.orders(g.faction_views[0].records(),g.selected,[],"wood")
 check("real menu enables observed wood transfer",candidate.size()==1 and not g.workforce_reassign_buttons.wood.disabled)
 for size in [Vector2i(390,844),Vector2i(844,390),Vector2i(320,568)]:
  root.size=size;g._layout_ui();await process_frame;await process_frame
  var button=g.workforce_reassign_buttons.wood
  check("transfer target fits menu width "+str(size),button.size.x>=140 and button.get_global_rect().position.x>=g.shortcut_scroll.get_global_rect().position.x and button.get_global_rect().end.x<=g.shortcut_scroll.get_global_rect().end.x)
 g.paused=true;g._refresh_idle_dispatch_buttons();g._reassign_selected_workforce("wood")
 check("pause cannot submit transfer",g.commands.is_empty())
 g.paused=false;g._refresh_idle_dispatch_buttons()
 g.build_mode="house";var saved_selection=g.selected.duplicate();g.selected=[]
 g._reassign_selected_workforce("wood")
 check("changed selection rejects without retiring old mode",g.commands.is_empty() and g.build_mode=="house")
 g.selected=saved_selection;g.touch_command=true;g._refresh_idle_dispatch_buttons()
 var cargo=g._cargo_amount(worker);var food=g.economy.bank_milli(0).food
 g._reassign_selected_workforce("wood")
 check("successful transfer retires build and targeting modes",g.build_mode=="" and not g.touch_command and not g.compact_menu.visible)
 check("menu queues ordinary order only",g.commands.size()==1 and g.commands[0].type=="order" and g.commands[0].work_reassign=="wood")
 var order=g.commands.pop_front();g._execute(order)
 check("transfer keeps cargo and enters delivery",g._cargo_amount(worker)==cargo and g._cargo_type(worker)=="food" and worker.state=="deliver" and worker.gather_type=="wood")
 var epoch=worker.work_epoch;g._execute(order)
 check("duplicate stale transfer cannot reset work",worker.work_epoch==epoch)
 var new_cargo=false
 for i in 2400:
  g._tick(.05)
  if g._cargo_amount(worker)>0 and g._cargo_type(worker)=="wood":new_cargo=true;break
 check("old food deposited before new wood gathered",g.economy.bank_milli(0).food>=food+cargo and new_cargo)
 g._update_vision(false);g._publish_faction_views()
 var stale=Policy.orders(g.faction_views[0].records(),[worker.id],[],"food")
 check("reverse plan available",stale.size()==1)
 if not stale.is_empty():
  var target=g._get_entity(stale[0].target);target.alive=false
  var before_epoch=worker.work_epoch;var before_cargo=g._cargo_amount(worker)
  g._execute(dict_order(stale[0]))
  check("invalid target cannot interrupt current work",worker.work_epoch==before_epoch and g._cargo_amount(worker)==before_cargo)
  target.alive=true
  g._set_stance(worker,"STOP");var cargo_after=g._cargo_amount(worker);g._execute(dict_order(stale[0]))
  check("newer stop survives stale reassignment",worker.mode=="STOP" and worker.state=="idle" and g._cargo_amount(worker)==cargo_after)
 check("economy ledger conserved",g.economy.audit().ok)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"workforce_reassign_contract","checks":checks,"failed":failed,"scope":"Selected-work policy and controlled actual native cargo delivery and resource switch; no saved files or phone/rendering acceptance"}))
 g.queue_free();quit(1 if failed else 0)
func dict_order(fields):
 var c=fields.duplicate(true);c.type="order";c.team=0;return c
