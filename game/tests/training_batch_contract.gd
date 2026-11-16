extends SceneTree
const Batch=preload("res://scripts/training_batch.gd")
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
	var b={"id":1,"owned":true,"alive":true,"team":0,"category":"building","kind":"barracks","built":true,"queue":[]};var bank={"food":999000,"wood":999000,"stone":999000,"iron":999000}
	check("batch capped at three",Batch.plan(b,bank,10,[],true).count==3)
	check("population cap respected",Batch.plan(b,bank,1,[],true).count==1)
	var crowded=b.duplicate(true);crowded.queue=[{},{},{},{}]
	check("queue cap respected",Batch.plan(crowded,bank,10,[],true).count==1)
	crowded.queue.append({});check("full queue refused",Batch.plan(crowded,bank,10,[],true).count==0)
	var exact={}
	for r in Rules.COSTS.spearman:exact[r]=Rules.COSTS.spearman[r]*1000
	check("affordability count",Batch.plan(b,exact,10,[],true).count==1)
	check("no funds refused",Batch.plan(b,{},10,[],true).count==0)
	check("pending own command waits",Batch.plan(b,bank,10,[{"type":"train","team":0}],true).count==0)
	check("locked unit refused",Batch.plan(b,bank,10,[],false).count==0)
	for patch in [{"owned":false},{"alive":false},{"remembered":true},{"team":1},{"built":false},{"kind":"town_center"}]:
		var changed=b.duplicate(true);changed.merge(patch,true);check("exclude "+str(patch),Batch.plan(changed,bank,10,[],true).count==0)
	var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset([{"food":500,"wood":500,"stone":100,"iron":100},{"food":150,"wood":200,"stone":100,"iron":0}]);g.set_process(false);await process_frame
	var center=g._first(0,"town_center");var barracks=g._spawn("barracks",0,center.pos+Vector3(6,0,0));g._update_vision();g._select([barracks.id]);g._update_hud()
	var before=g.economy.bank_milli(0).duplicate();var population=g._population(0);var plan=g._training_batch_plan(barracks.id)
	check("controlled building offers three",plan.count==3 and not g.training_batch_button.disabled)
	g._request_training_batch(barracks.id);check("three ordinary orders submitted",g.commands.size()==3 and g.commands.all(func(c):return c.type=="train" and c.kind=="spearman"))
	g._request_training_batch(barracks.id);check("rapid repeat does not duplicate batch",g.commands.size()==3)
	while not g.commands.is_empty():g._execute(g.commands.pop_front())
	var paid=true
	for r in Rules.COSTS.spearman:paid=paid and g.economy.bank_milli(0)[r]==before[r]-Rules.COSTS.spearman[r]*3000
	check("ordinary payment and population reservations",paid and barracks.queue.size()==3 and g._population(0)==population+3)
	g._update_vision();g._update_hud();g.training_batch_button.set_meta("squad_ids",[]);g._request_training_batch(barracks.id)
	check("stale displayed budget rejected",g.commands.is_empty())
	check("economy conserved",g.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size();print(JSON.stringify({"suite":"training_batch_contract","checks":checks,"failed":failed,"scope":"Controlled completed production building, normal training payments; not earned progression or physical phone acceptance"}));g.queue_free();quit(1 if failed else 0)
