extends SceneTree
const Policy=preload("res://scripts/player_scout_dispatch.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var mask=PackedByteArray();mask.resize(6400)
 var scout={"id":1,"owned":true,"alive":true,"remembered":false,"team":0,"kind":"scout","category":"unit","state":"idle","pos":Vector3(-25,0,24),"work_epoch":0}
 var home={"id":2,"owned":true,"alive":true,"remembered":false,"team":0,"kind":"town_center","pos":Vector3(-25,0,24)}
 var records={1:scout,2:home};var before=records.duplicate(true);var p=Policy.plan(records,[],mask)
 check("nearby public frontier produces ordinary ground order",not p.is_empty() and p.target==-1 and p.position.distance_to(scout.pos)<=18)
 check("uses public centre heading not hidden enemy",p.position.x>scout.pos.x and p.position.z<scout.pos.z)
 check("no observation mutation",records==before)
 check("pending order retained",Policy.plan(records,[{"team":0,"ids":[1]}],mask).is_empty())
 scout.state="move";check("moving scout not commandeered",Policy.plan(records,[],mask).is_empty());scout.state="idle"
 scout.path_status="LIMIT_REACHED";check("terminal path budget not reset",Policy.plan(records,[],mask).is_empty());scout.path_status="IDLE"
 mask.fill(1);check("fully explored map no order",Policy.plan(records,[],mask).is_empty());mask.fill(0)
 var hidden={"id":3,"alive":true,"remembered":true,"team":1,"category":"unit","pos":p.position};records[3]=hidden
 check("remembered enemy not treated as live truth",Policy.plan(records,[],mask)==p)
 hidden.remembered=false
 check("currently observed threat changes goal",Policy.plan(records,[],mask)!=p)
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.set_process(false);g.ai_enabled=false;await process_frame
 g.paused=false;g.application_focused=true;g.application_suspended=false
 var actor=g._first(0,"scout");g._set_stance(actor,"STOP");g._update_vision(false);g._publish_faction_views();g.compact_menu.show();g._refresh_idle_dispatch_buttons()
 check("real menu offers idle scout leg",not g.scout_dispatch_button.disabled)
 var old=g.scout_dispatch_button.get_meta("squad_ids",[]);g.gui_touch_press[65]={"button":weakref(g.scout_dispatch_button)};g._set_stance(actor,"STOP");g._publish_faction_views();g.build_mode="house";g.touch_command=true;g._dispatch_player_scout()
 check("old held plan rejected before cancelling mode",g.commands.is_empty() and g.build_mode=="house" and g.touch_command and not g.gui_touch_press.has(65))
 g._refresh_idle_dispatch_buttons()
 for size in [Vector2i(390,844),Vector2i(844,390),Vector2i(320,568)]:
  root.size=size;g._layout_ui();await process_frame;await process_frame
  check("scout action fits menu width "+str(size),g.scout_dispatch_button.size.x>=160 and g.scout_dispatch_button.get_global_rect().end.x<=g.shortcut_scroll.get_global_rect().end.x)
 var explored=g.explored_cells[0].count(1);var start=actor.pos;g._dispatch_player_scout()
 check("one guarded ordinary order and old modes retired",g.commands.size()==1 and g.commands[0].scout_dispatch and g.build_mode=="" and not g.touch_command)
 var order=g.commands[0].duplicate(true);var probe=order.duplicate(true);probe.erase("command_id");probe.source_work_epoch-=1;var epoch=actor.work_epoch;g._execute(probe)
 check("stale epoch preserves idle scout",actor.work_epoch==epoch and actor.state=="idle")
 probe=order.duplicate(true);probe.erase("command_id");probe.scout_cell+=1;g._execute(probe)
 check("mismatched cell cannot redirect scout",actor.work_epoch==epoch and actor.state=="idle")
 check("planning does not reveal map",g.explored_cells[0].count(1)==explored)
 for i in 500:
  g._tick(.05)
  if actor.state=="idle" and actor.pos.distance_to(start)>1:break
 check("scout physically moves and reveals explored cells",actor.pos.distance_to(start)>1 and g.explored_cells[0].count(1)>explored)
 check("single leg ends without autonomous requeue",actor.state=="idle" and g.commands.is_empty())
 check("ledger conserved",g.economy.audit().ok)
 var bench={};var bm=PackedByteArray();bm.resize(6400);bm.fill(1);bm[40*80+40]=0
 for i in 50:
  bench[i]={"id":i,"owned":true,"alive":true,"remembered":false,"team":0,"kind":"scout","state":"idle","pos":Vector3(-30,0,-30)}
  bench[100+i]={"id":100+i,"alive":true,"remembered":false,"team":1,"category":"unit","pos":Vector3(20+(i%5),0,20+(i/5))}
 var t=Time.get_ticks_usec();var bp=Policy.plan(bench,[],bm);var elapsed=Time.get_ticks_usec()-t
 check("max population no nearby frontier yields no order",bp.is_empty())
 print("PLANNER_BENCHMARK ",JSON.stringify({"scouts":50,"known_threats":50,"microseconds":elapsed,"scope":"headless local sample, not phone FPS"}))
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"player_scout_dispatch_contract","checks":checks,"failed":failed,"scope":"Public exploration mask policy and actual native one-leg scouting; no phone/rendered acceptance, no unseen terrain safety guarantee"}));g.queue_free();quit(1 if failed else 0)
