extends SceneTree
const Policy=preload("res://scripts/batch_construction_dispatch.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var r={}
 for i in 5:
  r[i]={"id":i,"owned":true,"alive":true,"remembered":false,"team":0,"category":"unit","kind":"villager","state":"idle","pos":Vector3(i,0,0),"cargo_milli":0,"work_epoch":0}
  r[10+i]={"id":10+i,"owned":true,"alive":true,"remembered":false,"team":0,"category":"building","kind":"barracks","built":false,"progress":i*.1,"pos":Vector3(i*3,0,4)}
 r[10].kind="house";var before=r.duplicate(true);var p=Policy.orders(r,[])
 check("three distinct workers and sites bounded",p.size()==3 and p[0].ids!=p[1].ids and p[1].ids!=p[2].ids and p[0].target!=p[1].target and p[1].target!=p[2].target)
 check("housing then most complete site",p[0].target==10 and p[1].target==14)
 check("observation not mutated",r==before)
 r[0].state="build";r[0].target=10
 check("existing builder retained",Policy.orders(r,[]).all(func(o):return o.target!=10 and o.ids!=[0]))
 for i in 5:r[i].cargo_milli=1000
 check("cargo workers not borrowed",Policy.orders(r,[]).is_empty())
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.set_process(false);g.ai_enabled=false;await process_frame
 g.paused=false;g.application_focused=true;g.application_suspended=false
 var workers=[]
 for w in g.entities:
  if w.team==0 and w.kind=="villager":workers.append(w)
 var bank0=g.economy.bank_milli(0).wood;var sites=[]
 for i in 2:
  var point=Vector3.INF
  for z in range(-7,8):
   for x in range(-7,8):
    var pnt=g._snap_build_position("house",g.MapRoutes.PLAYER_HOME+Vector3(x,0,z))
    if g._placement_reason("house",pnt,0,workers[i].id).is_empty():point=pnt;break
   if point!=Vector3.INF:break
  if point==Vector3.INF:check("legal construction site",false);break
  sites.append(g._place_building("house",point,workers[i].id,0))
 check("two normally paid construction sites",sites.size()==2 and g.economy.bank_milli(0).wood==bank0-100000)
 if sites.size()!=2:finish(g);return
 for i in 400:
  g._tick(.05)
  if sites[0].build_ticks>=20 and sites[1].build_ticks>=20:break
 check("both sites earn original physical construction progress",sites[0].build_ticks>=20 and sites[1].build_ticks>=20)
 for w in workers:g._set_stance(w,"STOP")
 var progress=[sites[0].build_ticks,sites[1].build_ticks];var bank=g.economy.bank_milli(0).duplicate()
 g._update_vision(false);g._publish_faction_views();g.compact_menu.show();g._refresh_idle_dispatch_buttons()
 check("menu finds two unattended paid sites",not g.batch_construction_button.disabled and g.batch_construction_button.get_meta("squad_ids",[]).size()==2)
 var initial=g.batch_construction_button.get_meta("squad_ids",[]);g.gui_touch_press[77]={"button":weakref(g.batch_construction_button)}
 g._set_stance(g._get_entity(initial[0].ids[0]),"STOP");g._publish_faction_views();g.build_mode="house";g.touch_command=true;g._dispatch_batch_construction()
 check("stale held plan cannot dispatch or cancel mode",g.commands.is_empty() and g.build_mode=="house" and g.touch_command and not g.gui_touch_press.has(77))
 g._refresh_idle_dispatch_buttons()
 for size in [Vector2i(390,844),Vector2i(844,390),Vector2i(320,568)]:
  root.size=size;g._layout_ui();await process_frame;await process_frame
  check("construction action fits width "+str(size),g.batch_construction_button.size.x>=160 and g.batch_construction_button.get_global_rect().end.x<=g.shortcut_scroll.get_global_rect().end.x)
 g._dispatch_batch_construction()
 check("normal two worker commands and mode retirement",g.commands.size()==2 and g.commands.all(func(c):return c.type=="order" and c.construction_dispatch and c.construction_batch) and g.build_mode=="" and not g.touch_command)
 check("resume retains paid progress without second charge",g.economy.bank_milli(0)==bank and sites[0].build_ticks==progress[0] and sites[1].build_ticks==progress[1])
 var probe=g.commands[0].duplicate(true);probe.erase("command_id");var worker=g._get_entity(probe.ids[0]);var site=g._get_entity(probe.target);var epoch=worker.work_epoch
 var malformed=probe.duplicate(true);malformed.erase("construction_dispatch");g._execute(malformed)
 check("malformed batch marker rejected",worker.work_epoch==epoch and worker.state=="idle")
 site.built=true;g._execute(probe);site.built=false
 check("finished site cannot turn resume into movement",worker.work_epoch==epoch and worker.state=="idle")
 var foe=g._spawn("spearman",1,site.pos+Vector3(3,0,0));g._update_vision(false);g._publish_faction_views();g._execute(probe)
 check("new observed threat rejects stale dispatch",worker.work_epoch==epoch and worker.state=="idle")
 g._kill(foe);g._update_vision(false);g._publish_faction_views()
 for i in 1500:
  g._tick(.05)
  if sites[0].built and sites[1].built:break
 check("both real original buildings completed",sites[0].built and sites[1].built)
 check("completion never repurchases sites",g.economy.bank_milli(0)==bank)
 check("ledger conserved",g.economy.audit().ok)
 finish(g)
func finish(g):
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"batch_construction_dispatch_contract","checks":checks,"failed":failed,"scope":"Controlled paid sites, actual Economy callback and ordinary physical completion; no saves or phone/rendered acceptance"}));g.queue_free();quit(1 if failed else 0)
