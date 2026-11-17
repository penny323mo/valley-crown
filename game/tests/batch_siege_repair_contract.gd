extends SceneTree
const Policy=preload("res://scripts/batch_repair_dispatch.gd")
var checks=[]
func check(n,b):
 checks.append({"name":n,"passed":bool(b)})
 if not b:push_error(n)
func refresh(g):
 g._update_vision(false);g._publish_faction_views();g.compact_menu.show();g._refresh_idle_dispatch_buttons()
func _initialize():call_deferred("run")
func run():
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.set_process(false);g.ai_enabled=false
 await process_frame
 g.paused=false;g.application_focused=true;g.application_suspended=false
 var a=g._spawn("siege",0,Vector3(-25,0,11));var b=g._spawn("siege",0,Vector3(-28,0,11))
 for e in [a,b]:e.hp-=10;e.last_damage_tick=-1000
 check("controlled siege positions are statically legal",g._static_unit_step_is_free(a,a.pos) and g._static_unit_step_is_free(b,b.pos))
 refresh(g)
 var records=g.faction_views[0].records();var before=records.duplicate(true);var plan=Policy.orders(records,[],g.tick_count)
 check("two damaged stationary siege get distinct workers",plan.size()==2 and plan[0].ids!=plan[1].ids and plan[0].target!=plan[1].target)
 check("policy leaves observed data intact",records==before)
 check("menu names siege maintenance",g.batch_repair_button.text.contains("攻城車") and not g.batch_repair_button.disabled)
 var pending=[]
 for o in plan:
  var c=o.duplicate(true);c.type="order";c.team=0;pending.append(c)
 check("pending orders prevent duplicate dispatch",Policy.orders(records,pending,g.tick_count).is_empty())
 var copy=records.duplicate(true);copy[a.id].state="move";copy[b.id].path_pending=true
 check("moving and pending siege excluded",Policy.orders(copy,[],g.tick_count).is_empty())
 copy=records.duplicate(true);copy[a.id].last_damage_tick=g.tick_count;copy[b.id].team=1;copy[b.id].owned=false
 check("recently hit and enemy siege excluded",Policy.orders(copy,[],g.tick_count).is_empty())
 copy=records.duplicate(true);copy[a.id].remembered=true;copy[b.id].kind="cavalry"
 check("remembered and living troop targets excluded",Policy.orders(copy,[],g.tick_count).is_empty())
 copy=records.duplicate(true)
 for id in copy:
  if copy[id].kind=="villager":copy[id].state="gather"
 check("existing gather workers are not commandeered",Policy.orders(copy,[],g.tick_count).is_empty())
 copy=records.duplicate(true);copy[9999]={"id":9999,"owned":false,"alive":true,"remembered":false,"team":1,"category":"unit","kind":"spearman","pos":a.pos}
 check("observed enemy prevents dangerous fleet dispatch",Policy.orders(copy,[],g.tick_count).is_empty())
 var wood=g.economy.bank_milli(0).wood;var hp=a.hp+b.hp
 g._dispatch_batch_repair()
 check("batch only queues ordinary guarded commands",g.commands.size()==2 and g.commands.all(func(c):return c.type=="order" and c.repair_batch and c.repair_dispatch))
 check("click gives no instant health or payment",a.hp+b.hp==hp and g.economy.bank_milli(0).wood==wood)
 var workers=[];var positions=[]
 for c in g.commands:workers.append(c.ids[0]);positions.append(g._get_entity(c.ids[0]).pos)
 for i in 900:
  g._tick(.05)
  if a.hp==a.max_hp and b.hp==b.max_hp:break
 check("both siege fully repaired by ordinary game ticks",a.hp==a.max_hp and b.hp==b.max_hp)
 check("exact four wood pays twenty health",g.economy.bank_milli(0).wood==wood-4000)
 check("workers physically travelled to targets",g._get_entity(workers[0]).pos.distance_to(positions[0])>1 and g._get_entity(workers[1]).pos.distance_to(positions[1])>1)
 check("completed workers stop without repeat charge",workers.all(func(id):return g._get_entity(id).state=="idle"))
 var paid=g.economy.bank_milli(0).wood
 for i in 40:g._tick(.05)
 check("healthy fleet causes no continuing expense",g.economy.bank_milli(0).wood==paid)
 # Target changes after UI planning must fail at authoritative execution.
 a.hp-=10;a.last_damage_tick=-1000;refresh(g)
 var stale=Policy.orders(g.faction_views[0].records(),[],g.tick_count)[0];stale.type="order";stale.team=0
 var worker=g._get_entity(stale.ids[0]);var epoch=worker.work_epoch
 g._submit("order",{"ids":[a.id],"target":-1,"position":Vector3(-22,0,10)})
 g._execute(g.commands.pop_front());g._execute(stale)
 check("siege moving before execution preserves worker epoch",worker.work_epoch==epoch and worker.state=="idle")
 g._set_stance(a,"STOP");refresh(g)
 g._dispatch_batch_repair();g._tick(.05)
 check("stationary target accepts fresh batch",worker.state=="repair")
 g._submit("order",{"ids":[a.id],"target":-1,"position":Vector3(-22,0,10)})
 paid=g.economy.bank_milli(0).wood;hp=a.hp
 for i in 10:g._tick(.05)
 check("target movement cancels active repair without extra heal",worker.state=="idle" and a.hp==hp and g.economy.bank_milli(0).wood==paid)
 g._set_stance(a,"STOP");g._set_stance(worker,"STOP");refresh(g)
 var remaining=g.economy.bank_milli(0).wood/1000
 var debit=g.economy.pay("v98_fixture_empty_wood",0,{"wood":remaining})
 check("controlled zero wood setup debits ledger",debit.applied and g.economy.bank_milli(0).wood==0)
 refresh(g);var count=g.commands.size();hp=a.hp
 g._dispatch_batch_repair()
 for i in 40:g._tick(.05)
 check("no wood disables batch and cannot heal for free",g.batch_repair_button.disabled and g.commands.size()==count and a.hp==hp)
 check("repair ledger conserves resources",g.economy.audit().ok)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"batch_siege_repair_contract","checks":checks,"failed":failed,"scope":"Controlled two-siege fixture; existing menu callback, normal travel and paid tick repair, no physical-phone claim."}))
 g.queue_free();quit(1 if failed else 0)
