extends SceneTree
const Dispatch=preload("res://scripts/farm_dispatch.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func worker(id,p):return {"id":id,"owned":true,"alive":true,"team":0,"category":"unit","kind":"villager","state":"idle","path":[],"path_pending":false,"pos":p,"cargo_milli":0}
func _initialize():call_deferred("run")
func run():
	var farm={"id":10,"owned":true,"alive":true,"team":0,"kind":"farm","built":true,"pos":Vector3.ZERO}
	var records={10:farm,1:worker(1,Vector3(2,0,0)),2:worker(2,Vector3(3,0,0))}
	check("nearest empty idle worker",Dispatch.plan(records,[],10,-1).worker==1)
	check("occupied farm rejected",Dispatch.plan(records,[],10,2).worker==-1)
	check("pending farm order rejects duplicate",Dispatch.plan(records,[{"type":"order","team":0,"ids":[1],"target":10}],10,-1).worker==-1)
	check("pending worker preserved",Dispatch.plan(records,[{"type":"stop","team":0,"ids":[1]}],10,-1).worker==2)
	for patch in [{"cargo_milli":1000},{"state":"gather"},{"path_pending":true},{"owned":false},{"alive":false}]:
		var r=records.duplicate(true);r[1].merge(patch,true)
		check("worker protected "+str(patch),Dispatch.plan(r,[],10,-1).worker==2)
	for patch in [{"built":false},{"owned":false},{"team":1},{"alive":false},{"remembered":true},{"kind":"house"}]:
		var r=records.duplicate(true);r[10].merge(patch,true)
		check("farm rejected "+str(patch),Dispatch.plan(r,[],10,-1).worker==-1)
	var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false);await process_frame
	var w=g._first(0,"villager")
	# Controlled registered farm near the worker; normal walking and ledger follow.
	var keep=g._first(0,"town_center");var point=Vector3.INF
	for z in range(-8,9):
		for x in range(-8,9):
			var p=g._snap_build_position("farm",keep.pos+Vector3(x,0,z))
			if g._placement_reason("farm",p,0,w.id).is_empty():point=p;break
		if point!=Vector3.INF:break
	check("controlled legal farm site found",point!=Vector3.INF)
	var payment=g._pay(g.Rules.COSTS.farm,0)
	check("controlled farm uses real payment",payment.applied)
	var f=g._spawn("farm",0,point,true);f.cost_receipt_id=payment.receipt_id
	g.economy.fulfill_cost("fulfilled:"+payment.receipt_id,payment.receipt_id,0)
	g._navigation_rebuild()
	g._update_vision();g._select([f.id]);g._update_hud()
	check("native selected farm offers dispatch",is_instance_valid(g.farm_dispatch_button) and not g.farm_dispatch_button.disabled)
	var bank=g.economy.bank_milli(0).duplicate();var chosen=g._farm_dispatch_plan(f.id).worker
	g.farm_dispatch_button.pressed.emit()
	check("one ordinary explicit farm order",g.commands.size()==1 and g.commands[0].get("farm_dispatch",false) and g.commands[0].get("farm_gather",false))
	g._request_farm_dispatch(f.id);check("repeat click cannot duplicate",g.commands.size()==1)
	check("dispatch does not mint food or change selection",g.economy.bank_milli(0)==bank and g.selected==[f.id])
	var command=g.commands.pop_front();g._execute(command)
	var farmer=g._get_entity(chosen)
	check("ordinary farm assignment accepted",farmer.state=="gather" and farmer.target==f.id)
	g._update_vision();g._refresh_farm_dispatch();check("occupied farm button disabled",g.farm_dispatch_button.disabled)
	var old_target=farmer.target;g._execute(command)
	check("stale execution cannot restart job",farmer.target==old_target and farmer.state=="gather")
	var earned=false
	for tick in 1200:
		g._tick(g.Rules.TICK)
		if g.economy.bank_milli(0).food>bank.food:earned=true;break
	check("native farming and delivery earns real food",earned)
	g.paused=true;g._refresh_farm_dispatch();var count=g.commands.size();g._request_farm_dispatch(f.id)
	check("paused farm action cannot command",g.commands.size()==count and g.farm_dispatch_button.disabled)
	check("ledger conserved",g.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"farm_dispatch_contract","checks":checks,"failed":failed,"scope":"Controlled registered farm with native farming and delivery; not natural expansion balance or physical phone acceptance"}))
	g.queue_free();quit(1 if failed else 0)
