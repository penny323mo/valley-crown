extends SceneTree
const Policy=preload("res://scripts/batch_repair_dispatch.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func command(o):
 var c=o.duplicate(true);c.type="order";c.team=0;return c
func _initialize():call_deferred("run")
func run():
 var r={}
 for i in 5:
  r[i]={"id":i,"owned":true,"alive":true,"remembered":false,"team":0,"category":"unit","kind":"villager","state":"idle","pos":Vector3(i,0,0),"cargo_milli":0,"work_epoch":0}
  r[10+i]={"id":10+i,"owned":true,"alive":true,"remembered":false,"team":0,"category":"building","kind":"house","built":true,"hp":100,"max_hp":250,"last_damage_tick":0,"pos":Vector3(i*3,0,4)}
 r[14].kind="town_center"
 var before=r.duplicate(true);var p=Policy.orders(r,[],100)
 check("three different buildings and workers bounded",p.size()==3 and p[0].ids!=p[1].ids and p[1].ids!=p[2].ids and p[0].target!=p[1].target and p[1].target!=p[2].target)
 check("main keep first",p[0].target==14)
 check("observation not changed",r==before)
 check("damage lockout prevents premature dispatch",Policy.orders(r,[],99).is_empty())
 var pending=[]
 for order in p:pending.append(command(order))
 var next=Policy.orders(r,pending,100)
 check("pending workers and targets not reused",next.all(func(o):return pending.all(func(c):return c.ids!=o.ids and c.target!=o.target)))
 for i in 5:r[i].cargo_milli=1000
 check("carrying workers protected",Policy.orders(r,[],100).is_empty())
 for i in 5:r[i].cargo_milli=0;r[i].state="gather"
 check("active work protected",Policy.orders(r,[],100).is_empty())
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.set_process(false);g.ai_enabled=false;await process_frame
 g.paused=false;g.application_focused=true;g.application_suspended=false
 var home=g._first(0,"town_center");home.hp=1000;home.last_damage_tick=-1000
 var tower=g._spawn("tower",0,home.pos+Vector3(8,0,0));tower.hp=400;tower.last_damage_tick=-1000
 var workers=[]
 for w in g.entities:
  if w.team==0 and w.kind=="villager":workers.append(w)
 workers[0].pos=home.pos+Vector3(3,0,0);workers[1].pos=tower.pos+Vector3(2,0,0)
 g._navigation_rebuild();g._update_vision(false);g._publish_faction_views();g.compact_menu.show();g._refresh_idle_dispatch_buttons()
 check("menu offers two actual repairs",not g.batch_repair_button.disabled and g.batch_repair_button.get_meta("squad_ids",[]).size()==2)
 for size in [Vector2i(390,844),Vector2i(844,390),Vector2i(320,568)]:
  root.size=size;g._layout_ui();await process_frame;await process_frame
  check("repair button fits menu width "+str(size),g.batch_repair_button.size.x>=160 and g.batch_repair_button.get_global_rect().end.x<=g.shortcut_scroll.get_global_rect().end.x)
 g.paused=true;g._refresh_idle_dispatch_buttons();g._dispatch_batch_repair()
 check("pause rejects batch",g.commands.is_empty())
 g.paused=false;g._refresh_idle_dispatch_buttons();g.build_mode="house";g.touch_command=true
 var previous=g.batch_repair_button.get_meta("squad_ids",[])
 g.gui_touch_press[88]={"button":weakref(g.batch_repair_button)}
 var stale_worker=g._get_entity(previous[0].ids[0]);g._set_stance(stale_worker,"STOP");g._publish_faction_views()
 g._dispatch_batch_repair()
 check("changed plan retires held touch",not g.gui_touch_press.has(88))
 check("stale menu plan rejected before mode cancellation",g.commands.is_empty() and g.build_mode=="house" and g.touch_command)
 g._refresh_idle_dispatch_buttons()
 var bank=g.economy.bank_milli(0).wood;g._dispatch_batch_repair()
 check("successful batch retires armed modes",g.build_mode=="" and not g.touch_command and not g.compact_menu.visible)
 check("queues distinct ordinary guarded repairs",g.commands.size()==2 and g.commands.all(func(c):return c.type=="order" and c.repair_dispatch and c.repair_batch))
 check("request has not healed or charged",home.hp==1000 and tower.hp==400 and g.economy.bank_milli(0).wood==bank)
 var stale=g.commands[0].duplicate(true);var w=g._get_entity(stale.ids[0]);g._set_stance(w,"STOP");var epoch=w.work_epoch;g._execute(stale)
 check("new Stop survives stale queued repair",w.work_epoch==epoch and w.state=="idle")
 # Leave only the other non-stale real command to observe repair payment.
 g.commands=g.commands.filter(func(c):return c.ids!=stale.ids)
 var other=g._get_entity(g.commands[0].target);var hp=other.hp
 var probe=g.commands[0].duplicate(true);probe.erase("command_id")
 var repairer=g._get_entity(probe.ids[0]);var original_epoch=repairer.work_epoch
 var malformed=probe.duplicate(true);malformed.erase("repair_dispatch");g._execute(malformed)
 check("malformed batch without dispatch rejected",repairer.work_epoch==original_epoch and repairer.state=="idle")
 other.hp=other.max_hp;g._execute(probe)
 check("completed repair before execution preserves worker",repairer.work_epoch==original_epoch and repairer.state=="idle")
 other.hp=hp
 var foe=g._spawn("spearman",1,other.pos+Vector3(4,0,0));g._update_vision(false);g._publish_faction_views();g._execute(probe)
 check("new observed threat before execution rejects batch",repairer.work_epoch==original_epoch and repairer.state=="idle")
 g._kill(foe);g._update_vision(false);g._publish_faction_views()
 for i in 400:
  g._tick(.05)
  if other.hp>hp:break
 check("actual worker repair increases HP and pays wood",other.hp>hp and g.economy.bank_milli(0).wood<bank)
 check("ledger conserved",g.economy.audit().ok)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"batch_repair_dispatch_contract","checks":checks,"failed":failed,"scope":"Controlled native Economy menu, stale orders and real paid repair; no phone/rendering acceptance"}));g.queue_free();quit(1 if failed else 0)
