extends SceneTree
const E=preload("res://scripts/economy_ledger.gd")
var g
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func ticks(count):
 for i in count:
  g.tick_count+=1
  for e in g.entities:
   if e.alive and e.category=="building":g._update_production(e,g.Rules.TICK,false)
  g._process_ready_production()
func _initialize():call_deferred("run")
func run():
 var ledger=E.new(E.FOUR_RESOURCE_TYPES);ledger.initialize([{"food":0,"wood":0},{"food":0,"wood":0}]);ledger.register_worker(1,0);ledger.register_worker(2,1);ledger.register_node(3,"wood",100000)
 for tick in range(1,251):ledger.gather_tick(1,3,tick);ledger.gather_tick(2,3,tick)
 check("ordinary capacity remains ten",ledger.worker_view(1).cargo_milli==10000 and ledger.worker_view(2).cargo_milli==10000)
 check("invalid upgrade rejected",not ledger.complete_wheelbarrow(-1,250).applied and not ledger.complete_wheelbarrow(0,-1).applied)
 check("completion records no money or free cargo",ledger.complete_wheelbarrow(0,250).applied and ledger.worker_view(1).cargo_milli==10000 and ledger.bank_milli(0).wood==0)
 check("completion tick preserves original capacity",ledger.cargo_capacity(0,250)==10000 and ledger.cargo_capacity(0,251)==15000)
 check("faction capacity isolated",ledger.cargo_capacity(1,251)==10000)
 check("cannot stack duplicate upgrades",not ledger.complete_wheelbarrow(0,251).applied)
 check("gather rate remains forty milli",ledger.gather_tick(1,3,251).amount_milli==40)
 for tick in range(252,400):ledger.gather_tick(1,3,tick)
 check("harvest fills exactly fifteen",ledger.worker_view(1).cargo_milli==15000 and not ledger.gather_tick(1,3,401).applied)
 check("deposit exact upgraded cargo",ledger.deposit("deposit",1,ledger.worker_view(1).cargo_revision).applied and ledger.bank_milli(0).wood==15000)
 ledger.register_worker(4,0);ledger.register_farm(5,0);ledger.assign_farm("farm",4,5)
 check("farm rate unchanged thirty milli",ledger.farm_tick(4,5,251).amount_milli==30)
 for tick in range(252,800):ledger.farm_tick(4,5,tick)
 check("new worker and farm respect upgraded cap",ledger.worker_view(4).cargo_milli==15000 and not ledger.farm_tick(4,5,801).applied)
 check("finite nodes and farm generation conserve",ledger.audit().ok)
 g=load("res://main.tscn").instantiate();root.add_child(g);g.test_mode=true;g.ai_enabled=false;g.set_process(false);g._test_reset([{"food":2000,"wood":2000,"stone":1000,"iron":1000},{"food":2000,"wood":2000,"stone":1000,"iron":1000}]);g.set_process(false);await process_frame
 var keep=g._first(0,"town_center")
 check("age one cannot buy wheelbarrow",not g._enqueue_military_research(keep.id,"wheelbarrow",0))
 g._enqueue_research(keep.id,0);ticks(1800);g.tick_count+=1
 var before=g.economy.bank_milli(0).duplicate()
 check("ordinary paid research queued",g._enqueue_military_research(keep.id,"wheelbarrow",0))
 check("cost food150 wood100",g.economy.bank_milli(0).food==before.food-150000 and g.economy.bank_milli(0).wood==before.wood-100000)
 check("duplicate pending denied",not g._enqueue_military_research(keep.id,"wheelbarrow",0))
 var item=keep.queue[0]
 check("cancel refunds ordinary receipt",g._cancel_queue_item(keep.id,item.queue_id,g.economy.quote_refund(item.receipt_id,0),0) and g.economy.bank_milli(0)==before and g.economy.cargo_capacity(0,g.tick_count)==10000)
 g._enqueue_military_research(keep.id,"wheelbarrow",0);ticks(900)
 check("game completion records upgrade but next tick activates",g.economy.cargo_capacity(0,g.tick_count)==10000 and g.military_tech_completed[0].has("wheelbarrow"))
 g.tick_count+=1
 check("game uses upgraded capacity",g.economy.cargo_capacity(0,g.tick_count)==15000 and g.economy.cargo_capacity(1,g.tick_count)==10000)
 check("economic tech never adds attack bonus",g._military_attack_bonus("villager",0)==0)
 g._publish_faction_views();g._select([keep.id]);g._update_hud()
 var b=g.actions.get_node_or_null("wheelbarrow")
 check("town center exposes completed wheelbarrow",b!=null and b.disabled and "已完成" in b.text and "15" in b.text)
 var worker=g._first(0,"villager")
 var tree={};var distance=INF
 for e in g.entities:
  if e.alive and e.kind in ["pine","oak"] and g._visible_to(e,0) and e.pos.distance_squared_to(worker.pos)<distance:tree=e;distance=e.pos.distance_squared_to(worker.pos)
 var peak=0;var delivered=g.economy.audit()
 var initial_wood=g.economy.bank_milli(0).wood
 if not tree.is_empty():
  g._order(worker,"gather",tree.id)
  for i in 1600:
   g._tick(g.Rules.TICK);peak=maxi(peak,g._cargo_amount(worker))
 check("actual worker route carries beyond ten",peak>10000 and peak<=15000)
 check("actual upgraded worker delivers ordinary wood",g.economy.bank_milli(0).wood>initial_wood)
 check("economic research preserves ledger",g.economy.audit().ok)
 g._test_reset();g.set_process(false);check("new match resets cargo capacity",g.economy.cargo_capacity(0)==10000)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"wheelbarrow_contract","build":g.Rules.BUILD_ID,"checks":checks,"failed":failed,"scope":"controlled funded authority and ledger checks, not physical mobile or natural match balance"}));g.queue_free();quit(1 if failed else 0)
