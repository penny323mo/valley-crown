extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
func c(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred("run")
func fresh():
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="standard";root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;return g
func run():
 var g=fresh();await process_frame
 var resource={}
 for e in g.entities:
  if e.alive and e.kind=="berry":resource=e;break
 # Explicit coherent sheltered-workforce fixture, no free stocks or unit birth.
 for w in g.entities:
  if not w.alive or w.team!=1 or w.kind!="villager":continue
  g._order_move(w,w.pos);w.gather_type="food";w.resource_target=resource.id;w.last_damage_tick=0
  w.ai_evacuation={"epoch":w.work_epoch,"resource":resource.id,"origin":resource.pos,"safe_since_tick":-1,"shelter_since_tick":-1,"hit_tick":0};g._ai_evacuation_wait(w)
 g._update_vision();g.ai_enabled=true;g.ai_budget=g.economy.bank_milli(1).duplicate()
 var workers=[]
 for r in g._ai_records():
  if r.owned and r.kind=="villager":workers.append(r)
 var keep=g._ai_owned(g._ai_records(),"town_center");var count=workers.size();var bank=g.economy.bank_milli(1).duplicate();var budget=g.ai_budget.duplicate()
 c("fixture is living sheltered workforce with ordinary funds",count>0 and count<8 and bank.food>=50000)
 c("housing priority never diverts into staffing",not g._ai_farm_shelter_staffing("house",workers,0,10,6,keep))
 c("nonfarm goals keep existing progression",not g._ai_farm_shelter_staffing("spearman",workers,0,10,6,keep))
 c("queued worker prevents duplicate relief",not g._ai_farm_shelter_staffing("farm",workers,1,10,6,keep))
 c("full population prevents relief",not g._ai_farm_shelter_staffing("farm",workers,0,6,6,keep))
 var many=workers.duplicate()
 while many.size()<8:many.append(workers[0])
 c("eight existing workers retain prior workforce ceiling",not g._ai_farm_shelter_staffing("farm",many,0,20,8,keep))
 g.ai_budget.food=49999
 c("one milli below price cannot enqueue",not g._ai_farm_shelter_staffing("farm",workers,0,10,6,keep));g.ai_budget=budget.duplicate()
 var w=g._get_entity(workers[0].id);var memo=w.ai_evacuation.duplicate(true);w.erase("ai_evacuation")
 c("any unsheltered live worker blocks extra recruitment",not g._ai_farm_shelter_staffing("farm",workers,0,10,6,keep));w.ai_evacuation=memo.duplicate(true)
 w.ai_evacuation.epoch+=1
 c("stale shelter epoch is not proof of unavailable labor",not g._ai_farm_shelter_staffing("farm",workers,0,10,6,keep));w.ai_evacuation=memo.duplicate(true)
 var unusable=keep.duplicate(true);unusable.built=false
 c("unfinished keep cannot train relief",not g._ai_farm_shelter_staffing("farm",workers,0,10,6,unusable))
 g.ai_enabled=false
 c("disabled AI never recruits",not g._ai_farm_shelter_staffing("farm",workers,0,10,6,keep));g.ai_enabled=true
 c("negative checks preserve bank and queue",g.economy.bank_milli(1)==bank and g.commands.is_empty() and g.ai_budget==budget)
 c("eligible relief submits ordinary train once",g._ai_farm_shelter_staffing("farm",workers,0,10,6,keep) and g.commands.size()==1)
 c("submission reserves fifty food but does not mint or debit early",g.ai_budget.food==budget.food-50000 and g.economy.bank_milli(1)==bank)
 c("pending ordinary train blocks same tick repeat",not g._ai_farm_shelter_staffing("farm",workers,0,10,6,keep) and g.commands.size()==1)
 var saved=Codec.capture_result(g);var encoded=Codec.encode(saved.data,g.Rules.BUILD_ID) if saved.ok else {"ok":false};var decoded=Codec.decode(encoded.bytes,g.Rules.BUILD_ID) if encoded.ok else {"ok":false}
 c("pending relief strict same build codec roundtrip",saved.ok and decoded.ok)
 if not decoded.ok:print("SAVED_FAILURE "+str(saved));finish(g);return
 var clone=fresh();var restored=Restore.apply(clone,decoded.data)
 c("pending relief restores without duplicate",restored and clone.commands==g.commands)
 if restored:clone._toggle_pause()
 g.ai_enabled=false;clone.ai_enabled=false
 for i in 100:g._tick(g.Rules.TICK);clone._tick(clone.Rules.TICK)
 var a=Codec.capture_result(g);var b=Codec.capture_result(clone)
 c("hundred normal ticks after restore preserve complete authority",a.ok and b.ok and a.data==b.data)
 c("normal execution pays exactly fifty food",g.economy.bank_milli(1).food==bank.food-50000)
 for i in 500:
  g._tick(g.Rules.TICK)
  if g._count(1,"villager")>count:break
 c("normal production ticks create exactly one new worker",g._count(1,"villager")==count+1)
 workers=[]
 for r in g._ai_records():
  if r.owned and r.kind=="villager":workers.append(r)
 g.ai_enabled=true;g.ai_budget=g.economy.bank_milli(1).duplicate()
 c("new worker without shelter permanently ends this relief episode",not g._ai_farm_shelter_staffing("farm",workers,0,10,7,g._ai_owned(g._ai_records(),"town_center")))
 c("ordinary economy remains conserved",g.economy.audit().ok)
 clone.free();finish(g)
func finish(g):
 var failed=0
 for row in checks:
  if not row.passed:failed+=1
 print(JSON.stringify({"suite":"ai_shelter_staffing_contract","checks":checks,"failed":failed,"scope":"Controlled coherent sheltered workforce with normal initial resources, paid training and strict continuation; no complete economy recovery claim."}))
 g.free();quit(0 if failed==0 else 1)
