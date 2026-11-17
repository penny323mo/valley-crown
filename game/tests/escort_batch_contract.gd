extends SceneTree
const Batch=preload("res://scripts/escort_batch.gd")
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
func unit(id,kind,p):return {"id":id,"kind":kind,"category":"unit","owned":true,"alive":true,"remembered":false,"team":0,"pos":p,"mode":"STOP"}
func run():
 var records={1:unit(1,"siege",Vector3.ZERO),2:unit(2,"siege",Vector3(6,0,0))}
 for i in range(3,7):records[i]=unit(i,"spearman",Vector3(i-3,0,-2))
 var selected=[1,2,3,4,5,6];var plan=Batch.plan(records,selected,[])
 check("two selected siege receive two guards each",plan.size()==2 and plan[0].ids.size()==2 and plan[1].ids.size()==2)
 check("deterministic reversed selection yields same plan",Batch.plan(records,[6,5,4,3,2,1],[])==plan)
 check("only selected units participate",Batch.plan(records,[1,3],[])==[{"target":1,"ids":[3]}])
 check("pending guard command excluded",not Batch.signature(Batch.plan(records,selected,[{"team":0,"ids":[3]}])).has(3))
 records[3].mode="ESCORT";records[3].escort_target=1
 plan=Batch.plan(records,selected,[])
 check("existing escort retained and counted toward balance",not Batch.signature(plan).has(3) and plan[0].ids.size()==1 and plan[1].ids.size()==2)
 records[3].escort_target=99
 check("existing escort outside selection not stolen",not Batch.signature(Batch.plan(records,selected,[])).has(3))
 records[3].mode="STOP"
 records[7]=unit(7,"siege",Vector3(12,0,0));records[8]=unit(8,"siege",Vector3(18,0,0))
 plan=Batch.plan(records,selected+[7,8],[])
 check("batch capped at three stable target ids",plan.size()==3 and plan.all(func(p):return p.target in [1,2,7]))
 for key in ["owned","alive","remembered","team"]:
  var copy=records.duplicate(true);copy[1][key]={"owned":false,"alive":false,"remembered":true,"team":1}[key]
  check("invalid selected target excluded "+key,Batch.plan(copy,selected,[]).all(func(p):return p.target!=1))
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;await process_frame
 var cars=[];var guards=[]
 for x in [8,14]:cars.append(g._spawn("siege",0,Vector3(x,0,-4)))
 for x in [7,9,13,15]:guards.append(g._spawn("spearman",0,Vector3(x,0,-7)))
 var outsider=g._spawn("cavalry",0,Vector3(18,0,-7))
 g._navigation_rebuild();g._update_vision();g._publish_faction_views()
 var ids=[]
 for car in cars:
  ids.append(car.id);g._submit("order",{"ids":[car.id],"target":-1,"position":car.pos+Vector3(0,0,5)})
 for guard in guards:ids.append(guard.id)
 g._select(ids);g._update_hud();await process_frame
 var button=g.escort_batch_button
 check("mixed selection exposes one batch action",is_instance_valid(button) and not button.disabled and button.name=="EscortBatch")
 g._start_advance_command();g._update_hud();button=g.escort_batch_button
 var pending=g.commands.size();button.pressed.emit()
 check("batch action cancels stale target designation mode",not g.touch_command and g.build_mode.is_empty())
 check("button queues two existing escort groups only",g.commands.size()==pending+2 and g.commands[-1].type=="escort" and g.commands[-2].type=="escort")
 button=g.escort_batch_button;button.pressed.emit();check("repeat before tick cannot duplicate batch",g.commands.size()==pending+2)
 var outside_mode=outsider.mode;var outside_epoch=outsider.work_epoch
 var bank=g.economy.bank_milli(0).duplicate(true);g._tick(Rules.TICK)
 check("normal tick commits two escorts per siege",guards.filter(func(u):return u.get("escort_target",-1)==cars[0].id).size()==2 and guards.filter(func(u):return u.get("escort_target",-1)==cars[1].id).size()==2)
 check("vehicle original movement survives batch",cars.all(func(c):return c.mode!="ESCORT" and c.state=="move" and c.dest.z>c.pos.z))
 check("unselected unit and resource bank unchanged",outsider.mode==outside_mode and outsider.work_epoch==outside_epoch and not outsider.has("escort_target") and g.economy.bank_milli(0)==bank)
 var epochs=[];var nexts=[]
 for guard in guards:epochs.append(guard.work_epoch);nexts.append(guard.escort_next_tick)
 g._publish_faction_views();g._update_hud();g._request_escort_batch()
 check("repeat after tick does not enqueue new escort",g.commands.is_empty())
 g._order_escort([guards[0].id],guards[0].escort_target,0)
 check("same-target ordinary escort is idempotent",guards[0].work_epoch==epochs[0] and guards[0].escort_next_tick==nexts[0])
 g._select(ids);g._update_hud()
 check("already escorting mixed selection keeps disabled discoverable action",is_instance_valid(g.escort_batch_button) and g.escort_batch_button.disabled)
 var starts=[]
 for guard in guards:starts.append(guard.pos)
 for i in 140:g._tick(Rules.TICK)
 check("two groups follow through normal simulation movement",guards.all(func(u):return u.mode=="ESCORT" and u.pos.z>-6.5) and cars.all(func(c):return c.pos.z>-2))
 var enemy=g._spawn("archer",1,cars[0].pos+Vector3(1.5,0,0));g._update_vision();var intercepted=false
 for i in 40:
  g._tick(Rules.TICK)
  for guard in guards:
   if guard.target==enemy.id and guard.state=="attack":intercepted=true
 check("ordinary escort logic intercepts nearby visible threat",intercepted)
 var other_target=guards[2].get("escort_target",-1)
 g._submit("stop",{"ids":[guards[0].id]});g._tick(Rules.TICK)
 check("manual stop exits one escort without canceling another",guards[0].mode=="STOP" and not guards[0].has("escort_target") and guards[2].get("escort_target",-1)==other_target)
 # Execute-time liveness gate: a queued target may die after UI planning.
 g._select([cars[1].id,guards[0].id]);g._publish_faction_views();g._update_hud();g._request_escort_batch()
 var epoch=guards[0].work_epoch;g._kill(cars[1]);g._tick(Rules.TICK)
 check("target death before execute does not redirect selected guard",guards[0].mode=="STOP" and guards[0].work_epoch==epoch and not guards[0].has("escort_target"))
 check("enemy observations never expose owned escort targets",not g.faction_views[1].get_record(guards[1].id).has("escort_target"))
 g.free();await process_frame
 print(JSON.stringify({"suite":"escort_batch_contract","checks":checks,"failed":checks.filter(func(c):return not c.passed).size(),"scope":"Owned selection planning and controlled ordinary command/tick follow/intercept; existing escort state only, no natural battle or phone claim."}))
 quit(1 if checks.any(func(c):return not c.passed) else 0)
