extends SceneTree
const Dispatch=preload("res://scripts/repair_dispatch.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false)
 var siege=g._spawn("siege",0,Vector3(-25,0,11));siege.hp-=30;siege.last_damage_tick=-1000
 g._update_vision();g._select([siege.id]);g._update_hud();await process_frame
 var plan=Dispatch.plan(g.faction_views[0].records(),g.commands,siege.id,g.tick_count)
 check("damaged stationary siege offers idle worker repair",plan.worker>=0 and is_instance_valid(g.repair_dispatch_button) and not g.repair_dispatch_button.disabled)
 var worker=g._get_entity(plan.worker);var before=g.economy.bank_milli(0).duplicate();var hp=siege.hp
 check("villager contextual intent resolves siege repair",g._target_order_intent(worker,siege,0)=="repair")
 g._request_repair_dispatch(siege.id)
 check("dispatch queues one ordinary order without healing or charge",g.commands.size()==1 and siege.hp==hp and g.economy.bank_milli(0)==before)
 g._execute(g.commands.pop_front())
 check("ordinary command starts repair",worker.state=="repair" and worker.target==siege.id)
 var slot=g._free_adjacent(siege,worker.pos,false,0,worker)
 check("legal disk-clear work position exists",slot!=Vector3.INF)
 if slot!=Vector3.INF:
  worker.pos=slot;worker.path.clear();worker.path_pending=false
  for i in 20:g.tick_count+=1;g._update_unit(worker,g.Rules.TICK)
 check("one wood repairs five siege HP",siege.hp==hp+5 and g.economy.bank_milli(0).wood==before.wood-1000)
 var paid=g.economy.bank_milli(0).wood;var healed=siege.hp
 siege.state="move";g.tick_count+=1;g._update_unit(worker,g.Rules.TICK)
 check("moving siege stops worker without free heal",worker.state=="idle" and siege.hp==healed and g.economy.bank_milli(0).wood==paid)
 check("moving target rejects fresh repair",not g._order(worker,"repair",siege.id))
 siege.state="attack";check("attacking target rejects repair",not g._order(worker,"repair",siege.id))
 siege.state="idle";siege.path_pending=true;check("pending route rejects repair",not g._order(worker,"repair",siege.id));siege.path_pending=false
 siege.last_damage_tick=g.tick_count;check("five second damage lockout",not g._order(worker,"repair",siege.id));siege.last_damage_tick=-1000
 siege.team=1;check("enemy siege rejects repair",not g._order(worker,"repair",siege.id));siege.team=0
 siege.kind="cavalry";check("living military cannot be wood repaired",not g._order(worker,"repair",siege.id));siege.kind="siege"
 siege.hp=siege.max_hp-2;g._order(worker,"repair",siege.id)
 worker.pos=g._free_adjacent(siege,worker.pos,false,0,worker);worker.path.clear();worker.path_pending=false
 for i in 20:g.tick_count+=1;g._update_unit(worker,g.Rules.TICK)
 check("repair caps max HP and stops",siege.hp==siege.max_hp and worker.state=="idle")
 check("all wood accounted as repair expense",g.economy.stats_view(0).repaired.wood==2000 and g.economy.audit().ok)
 g._update_vision();g._select([siege.id]);g._update_hud()
 check("healthy siege hides repair action",not is_instance_valid(g.repair_dispatch_button))
 g._test_reset();g.set_process(false)
 siege=g._spawn("siege",0,Vector3(-25,0,11));siege.hp-=10;siege.last_damage_tick=-1000
 g._update_vision();g._select([siege.id]);g._update_hud()
 plan=Dispatch.plan(g.faction_views[0].records(),g.commands,siege.id,g.tick_count)
 worker=g._get_entity(plan.worker);var departure=worker.pos;hp=siege.hp;before=g.economy.bank_milli(0).duplicate()
 g._request_repair_dispatch(siege.id)
 for i in 600:
  g._tick(g.Rules.TICK)
  if siege.hp>hp:break
 check("ordinary routed worker reaches siege and repairs without teleport",siege.hp>hp and worker.pos.distance_to(departure)>1 and g.economy.bank_milli(0).wood==before.wood-1000)
 check("routed repair ledger conserved",g.economy.audit().ok)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"siege_repair_contract","checks":checks,"failed":failed,"scope":"Native controlled siege and direct GUI callback; ordinary order and paid repair; not routed physical touch or natural battle acceptance"}))
 g.queue_free();quit(1 if failed else 0)
