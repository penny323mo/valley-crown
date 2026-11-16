extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
const Rest=preload("res://scripts/rest_recovery.gd")
const Retreat=preload("res://scripts/wounded_retreat.gd")
var checks=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred("run")
func fresh(mode="survival"):
 var g=load("res://main.tscn").instantiate();g.skirmish_mode=mode;g.history_path="/tmp/supply-contract-history-%d.json"%Time.get_ticks_usec();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;return g
func run():
 var g=fresh();await process_frame
 var station=g._spawn("storehouse",0,Vector3(-8,0,26),true)
 var bank=g.economy.bank_milli(0).duplicate()
 check("completed own age2 store can upgrade",g._enqueue_supply_upgrade(station.id,0))
 check("upgrade charges exact one hundred wood and food",g.economy.bank_milli(0).wood==bank.wood-100000 and g.economy.bank_milli(0).food==bank.food-100000)
 var charged=g.economy.bank_milli(0).duplicate();var rid=station.queue[0].receipt_id
 check("duplicate upgrade cannot pay twice",not g._enqueue_supply_upgrade(station.id,0) and g.economy.bank_milli(0)==charged)
 check("ordinary dropoff survives pending upgrade",g._valid_dropoff(g._first(0,"villager"),station))
 var initial=Codec.capture(g)
 check("queued upgrade is valid exact build checkpoint",not initial.is_empty())
 var Store=load("res://scripts/checkpoint_store.gd")
 var slot="/tmp/frontline-supply-isolated-%d.bin" % Time.get_ticks_usec()
 g.paused=true
 check("new upgrade saves to isolated ordinary slot",Store.save_slot(g,slot).ok)
 var bytes=FileAccess.get_file_as_bytes(slot)
 station.queue[0].remaining_ticks=601
 check("invalid upgrade cannot replace existing file",not Store.save_slot(g,slot).ok and FileAccess.get_file_as_bytes(slot)==bytes and not FileAccess.file_exists(slot+".tmp"))
 station.queue[0].remaining_ticks=600;DirAccess.remove_absolute(slot);g.paused=false
 var h=fresh();await process_frame
 check("queued upgrade restores detached candidate",Restore.apply(h,initial))
 # Supply-specific shape and ledger guards reject valid-checksum malformed data.
 for variant in ["remaining","nan","research","started","elapsed","extra","receipt","float_cost","duplicate_queue","duplicate_receipt"]:
  var d=initial.duplicate(true)
  for e in d.entities:
   if e.id!=station.id:continue
   if variant=="remaining":e.queue[0].remaining_ticks=601
   if variant=="nan":e.queue[0].remaining_ticks=NAN
   if variant=="research":e.queue[0].research=1
   if variant=="started":e.queue[0].started=true
   if variant=="elapsed":
    e.queue[0].started=true;e.queue[0].remaining_ticks=599
    d.modules.economy._receipts[rid].refund_policy="started"
   if variant=="extra":e.queue[0].unexpected=true
   if variant=="receipt":e.queue[0].receipt_id="absent"
   if variant in ["duplicate_queue","duplicate_receipt"]:
    var copy=e.duplicate(true);copy.id=d.game.next_id;d.game.next_id+=1
    if variant=="duplicate_receipt":copy.queue[0].queue_id=d.game.next_queue_id;d.game.next_queue_id+=1
    d.entities.append(copy);break
  if variant=="float_cost":d.modules.economy._receipts[rid].cost_units.food=100.0
  check("reject malformed queued upgrade "+variant,not Codec.validate(d))
 for size in [Vector2i(640,360),Vector2i(320,568)]:
  root.size=size;g._update_vision(false);g._publish_faction_views();g._select([station.id]);g._update_hud();g._layout_ui()
  for i in 3:await process_frame
  var upgrade=g.actions.get_node_or_null("SupplyStationUpgrade")
  var cancel=g.actions.get_node_or_null("CancelQueue%d" % station.queue[0].queue_id)
  check("station queue has reachable cancel and disabled duplicate action "+str(size),is_instance_valid(upgrade) and upgrade.disabled and upgrade.size.y>=44 and is_instance_valid(cancel) and cancel.size.y>=44)
  check("station progress displays remaining seconds "+str(size),g.queue_label.text.contains("前線補給站") and g.queue_label.text.contains("30s"))
 check("unstarted cancellation returns full cost",g._cancel_queue_item(station.id,station.queue[0].queue_id,g.economy.quote_refund(rid,0),0) and g.economy.bank_milli(0)==bank and not station.get("supply_station",false))
 check("upgrade can be purchased after cancellation",g._enqueue_supply_upgrade(station.id,0))
 g.tick_count+=1;g._update_production(station,.05)
 var quote=g.economy.quote_refund(station.queue[0].receipt_id,0)
 check("started upgrade has normal seventy five percent refund",quote.wood==75000 and quote.food==75000)
 check("started cancel does not grant station",g._cancel_queue_item(station.id,station.queue[0].queue_id,quote,0) and not station.get("supply_station",false))
 # Restored original purchase gets exactly its original 600 productive ticks.
 var hs=h._get_entity(station.id);h.paused=false
 for i in 599:h.tick_count+=1;h._update_production(hs,.05)
 check("no supply benefit before full thirty seconds",not hs.get("supply_station",false) and hs.queue[0].remaining_ticks==1)
 h.tick_count+=1;h._update_production(hs,.05)
 check("completion is individual and receipt fulfilled",hs.get("supply_station",false) and hs.queue.is_empty() and h.economy.receipt_view(hs.supply_receipt_id).state=="fulfilled")
 var hb=h.economy.bank_milli(0).duplicate()
 check("completed upgrade cannot repurchase",not h._enqueue_supply_upgrade(hs.id,0) and h.economy.bank_milli(0)==hb)
 check("completed station remains resource dropoff",h._valid_dropoff(h._first(0,"villager"),hs))
 h._update_vision(false);h._publish_faction_views();h._update_visuals(0)
 check("visible upgraded station has actual banner",hs.body.has_node("SupplyBanner") and hs.body.get_node("SupplyBanner").visible)
 h._select([hs.id]);h._update_hud();await process_frame
 check("selection distinguishes station name",h.selection_title.text=="前線補給站")
 var complete=Codec.capture(h);check("completed optional state validates",not complete.is_empty())
 var j=fresh();await process_frame
 check("completed station restores",Restore.apply(j,complete) and j._get_entity(hs.id).get("supply_station",false))
 j._update_vision(false);j._publish_faction_views();j._update_visuals(0)
 check("restored station recreates banner",j._get_entity(hs.id).body.has_node("SupplyBanner"))
 var frozen=Codec.capture(j);var forged=complete.duplicate(true)
 for e in forged.entities:
  if e.id==hs.id:e.supply_completed_tick=-1
 var payload=var_to_bytes(forged);var hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(payload)
 check("valid checksum cannot bypass supply verification",not Codec.decode(var_to_bytes({"magic":Codec.MAGIC,"schema":Codec.SCHEMA,"build":h.Rules.BUILD_ID,"sha256":hash.finish().hex_encode(),"payload":payload}),h.Rules.BUILD_ID).ok)

 for variant in ["flag","missing_receipt","cost","time","early","age_type","wrong_kind","duplicate"]:
  var d=complete.duplicate(true)
  for e in d.entities:
   if e.id!=hs.id:continue
   if variant=="flag":e.supply_station=1
   if variant=="missing_receipt":e.erase("supply_receipt_id")
   if variant=="time":e.supply_completed_tick=d.game.tick_count+1
   if variant=="early":e.supply_completed_tick=599
   if variant=="wrong_kind":e.kind="house";e.max_hp=h.Rules.HP.house;e.hp=250
   if variant=="duplicate":
    var copy=e.duplicate(true);copy.id=d.game.next_id;d.game.next_id+=1;d.entities.append(copy);break
  if variant=="cost":d.modules.economy._receipts[hs.supply_receipt_id].cost_units.wood=99
  if variant=="age_type":d.game.age_completed_tick[0]="bad"
  check("reject malformed station "+variant,not Codec.validate(d))
  var before=Codec.capture(j)
  check("malformed station cannot mutate candidate "+variant,not Restore.apply(j,d) and Codec.capture(j)==before)
 var ordinary=complete.duplicate(true)
 for e in ordinary.entities:
  for key in ["supply_station","supply_receipt_id","supply_completed_tick"]:e.erase(key)
 check("missing optional fields remains ordinary old shape",Codec.validate(ordinary))
 var worker=h._first(0,"villager")
 check("ordinary keep remains eligible",Rest.eligible_base(h._first(0,"town_center")))
 var raw=hs.duplicate();raw.erase("supply_station")
 check("ordinary storehouse cannot heal",not Rest.eligible_base(raw))
 raw=hs.duplicate();raw.alive=false;check("destroyed station cannot heal",not Rest.eligible_base(raw))
 var unit=h._first(0,"cavalry");unit.pos=hs.pos+Vector3(0,0,3);unit.node.position=unit.pos;unit.hp=unit.max_hp-10;h._set_stance(unit,"STOP");unit.last_damage_tick=-1000
 # Controlled recovery mechanism, distinct from the separate actual-combat journey.
 for i in 239:h.tick_count+=1;h._update_rest_recovery()
 check("safe waiting plus first interval does not heal early",unit.hp==unit.max_hp-10)
 h.tick_count+=1;h._update_rest_recovery()
 check("station heals one HP after ten plus two seconds",unit.hp==unit.max_hp-9)
 h._update_rest_recovery();check("same tick cannot stack recovery",unit.hp==unit.max_hp-9)
 unit.last_damage_tick=h.tick_count+1;h.tick_count+=1;h._update_rest_recovery();check("damage resets station safe wait",unit.rest_ticks==0)
 h._order_move(unit,unit.pos+Vector3(1,0,0));h.tick_count+=1;h._update_rest_recovery();check("movement interrupts recovery",unit.rest_ticks==0)
 var records={1:{"id":1,"owned":true,"alive":true,"built":true,"category":"building","kind":"town_center","team":0,"pos":Vector3(0,0,0)},2:{"id":2,"owned":true,"alive":true,"built":true,"category":"building","kind":"storehouse","supply_station":true,"team":0,"pos":Vector3(20,0,0)},3:{"id":3,"owned":true,"alive":true,"category":"unit","kind":"cavalry","team":0,"hp":50,"max_hp":110,"pos":Vector3(30,0,0)}}
 check("wounded retreat chooses nearest safe station",Retreat.orders(records,[3],[])[0].retreat_base==2)
 records[4]={"id":4,"alive":true,"category":"unit","kind":"spearman","team":1,"pos":Vector3(20,0,2)}
 check("visible station danger chooses farther safe keep",Retreat.orders(records,[3],[])[0].retreat_base==1)
 records[4].remembered=true
 check("remembered enemy cannot supply current danger",Retreat.orders(records,[3],[])[0].retreat_base==2)
 check("overlapping bases select one stable identity",Rest.base_for({"team":0,"pos":Vector3(4,0,0)},[records[1],{"id":2,"alive":true,"built":true,"kind":"storehouse","supply_station":true,"team":0,"pos":Vector3(5,0,0)}]).id==1)
 # Execution-time observations can invalidate a previously displayed retreat plan.
 unit.pos=hs.pos+Vector3(15,0,0);unit.node.position=unit.pos;h._set_stance(unit,"STOP")
 h._update_vision(false);h._publish_faction_views()
 var plan=Retreat.orders(h.faction_views[0].records(),[unit.id],[])
 check("actual retreat has safe forward station plan",plan.size()==1 and plan[0].retreat_base==hs.id)
 if plan.size()==1:
  var attacker=h._spawn("spearman",1,hs.pos+Vector3(1,0,0));h._update_vision(false);h._publish_faction_views()
  var epoch=unit.work_epoch;var prior=unit.state
  var command=plan[0].duplicate();command.type="order";command.team=0
  h._execute(command)
  check("new observed threat rejects stale retreat without cancelling prior order",unit.work_epoch==epoch and unit.state==prior)
  h._kill(attacker)
 # The restored counterpart retains a normal upgraded station even after destruction.
 var dead_station=j._get_entity(hs.id);j._kill(dead_station)
 check("completed dead station retains valid historical receipt but cannot heal",not Codec.capture(j).is_empty() and not Rest.eligible_base(dead_station))
 check("all ledgers conserve",g.economy.audit().ok and h.economy.audit().ok and j.economy.audit().ok)
 g.free();h.free();j.free()
 var p=fresh("practice");await process_frame
 var s=p._spawn("storehouse",0,Vector3(-8,0,26),true);var old=p.economy.bank_milli(0).duplicate()
 s.built=false
 check("unfinished store cannot upgrade",not p._enqueue_supply_upgrade(s.id,0) and p.economy.bank_milli(0)==old)
 s.built=true
 check("age1 rejected without payment",not p._enqueue_supply_upgrade(s.id,0) and p.economy.bank_milli(0)==old)
 check("wrong owner rejected without payment",not p._enqueue_supply_upgrade(s.id,1))
 p.age_completed_tick[0]=p.tick_count
 check("same tick age completion still rejects station",not p._enqueue_supply_upgrade(s.id,0) and p.economy.bank_milli(0)==old)
 p.tick_count+=1
 check("following tick accepts age gated station",p._enqueue_supply_upgrade(s.id,0))
 p._update_production(s,.05)
 for i in 599:p.tick_count+=1;p._update_production(s,.05)
 check("ordinary age boundary completes at six hundred productive ticks",s.get("supply_completed_tick",-1)==600 and not Codec.capture(p).is_empty())
 p.free()
 var destroyed=fresh();await process_frame
 var ds=destroyed._spawn("storehouse",0,Vector3(-8,0,26),true)
 destroyed._enqueue_supply_upgrade(ds.id,0)
 var paid_bank=destroyed.economy.bank_milli(0).duplicate();var paid_receipt=ds.queue[0].receipt_id
 destroyed._kill(ds)
 check("destruction closes purchase without refund or benefit",destroyed.economy.bank_milli(0)==paid_bank and ds.queue.is_empty() and not ds.get("supply_station",false) and destroyed.economy.receipt_view(paid_receipt).state=="destroyed")
 check("destroyed upgrade remains valid checkpoint",not Codec.capture(destroyed).is_empty())
 destroyed.free()
 var fog=fresh();await process_frame
 var enemy_store=fog._spawn("storehouse",1,fog._first(0,"town_center").pos+Vector3(5,0,0),true)
 fog._update_vision(false);fog._publish_faction_views();fog._update_visuals(0)
 check("enemy visible ordinary warehouse exposes no upgrade",not fog.faction_views[0].get_record(enemy_store.id).is_empty() and not fog.faction_views[0].get_record(enemy_store.id).get("supply_station",false))
 fog._enqueue_supply_upgrade(enemy_store.id,1)
 # Controlled visibility boundary, not an actual reconnaissance journey.
 fog.visible_cells[0].fill(0)
 for i in 600:fog.tick_count+=1;fog._update_production(enemy_store,.05)
 fog._publish_faction_views();fog._update_visuals(0)
 var memory=fog.faction_views[0].get_record(enemy_store.id)
 check("hidden completed upgrade cannot alter remembered warehouse",enemy_store.get("supply_station",false) and memory.get("remembered",false) and not memory.get("supply_station",false) and not fog.presentation_nodes[enemy_store.id].body.has_node("SupplyBanner"))
 fog._update_vision(false);fog._publish_faction_views();fog._update_visuals(0)
 check("reobserved completed enemy station gets real flag",fog.faction_views[0].get_record(enemy_store.id).get("supply_station",false) and fog.presentation_nodes[enemy_store.id].body.has_node("SupplyBanner"))
 fog.free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"frontline_supply_contract","checks":checks,"failed":failed,"scope":"Controlled funded upgrade, receipt, restore and recovery boundaries; not natural combat or physical phone proof"}))
 quit(1 if failed else 0)
