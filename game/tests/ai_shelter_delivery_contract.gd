extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
func c(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred("run")
func fresh():
 var g=load("res://main.tscn").instantiate();g.history_path="/tmp/shelter-test-%d.json"%Time.get_ticks_usec();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.skirmish_mode="standard"
 g._spawn("town_center",0,Vector3(22,0,22));g._spawn("town_center",1,Vector3(-10,0,-10));return g
func step(g,n=1):
 for i in n:
  g._tick(g.Rules.TICK)
  if g._update_ai_worker_safety():g._publish_faction_views()
func roundtrip(g):
 var result=Codec.capture_result(g)
 if not result.ok:print("CAPTURE_FAILURE "+str(result));return false
 var encoded=Codec.encode(result.data,g.Rules.BUILD_ID)
 if not encoded.ok:return false
 var decoded=Codec.decode(encoded.bytes,g.Rules.BUILD_ID)
 if not decoded.ok:return false
 var clone=fresh();var ok=Restore.apply(clone,decoded.data)
 if ok:
  var restored=Codec.capture_result(clone)
  ok=clone.paused and restored.ok and restored.data.entities==result.data.entities and restored.data.modules.economy==result.data.modules.economy
 clone.free();return ok
func fork_steps(g,n):
 var source=Codec.capture_result(g)
 if not source.ok:return false
 var clone=fresh()
 if not Restore.apply(clone,source.data):clone.free();return false
 clone._toggle_pause()
 for i in n:step(g);step(clone)
 var a=Codec.capture_result(g);var b=Codec.capture_result(clone)
 var equal=a.ok and b.ok and a.data==b.data
 clone.free();return equal
func run():
 var g=fresh();await process_frame
 var w=g._spawn("villager",1,Vector3(0,0,-10));var origin=g._spawn("berry",-1,Vector3(0,0,-11))
 g._navigation_rebuild();g._update_vision();g._order(w,"gather",origin.id);step(g,60)
 c("cargo earned by normal gathering",g._cargo_amount(w)>0)
 var foe=g._spawn("spearman",0,w.pos+Vector3(.8,0,0));g._update_vision();var hit=g._release_attack(foe,w);step(g)
 c("real hit creates ordinary evacuation",hit.applied and w.has("ai_evacuation") and w.state=="move")
 for i in 400:
  step(g)
  if w.state=="idle":break
 c("ordinary travel reaches shelter",w.state=="idle" and w.has("ai_evacuation") and w.path_status=="FOUND")
 c("original work area remains unobserved",g.visible_cells[1][g._cell_index(origin.pos)]==0)
 var cargo=g._cargo_amount(w);var bank=g.economy.bank_milli(1).food;var hp=w.hp
 step(g,99)
 c("shelter needs full safety interval",w.state=="idle" and w.has("ai_evacuation"))
 c("waiting checkpoint strict roundtrip",roundtrip(g))
 c("saved ninety nine tick shelter clock resumes identically",fork_steps(g,1) and w.state=="deliver")
 for i in 3:
  if w.state=="deliver":break
  step(g)
 c("unknown origin does not prevent safe delivery",w.state=="deliver" and w.has("ai_evacuation"))
 c("delivery preserves origin danger and earned cargo",w.ai_evacuation.resource==origin.id and g._cargo_amount(w)==cargo and g._ai_worker_resource_blocked(origin.pos))
 c("delivery does not reroute to unchecked depots",not w.work_any_target)
 c("delivery checkpoint strict roundtrip",roundtrip(g))
 c("delivery ten tick restored continuation is exact",fork_steps(g,10))
 var blind_return=false
 for i in 500:
  step(g)
  blind_return=blind_return or (w.state=="gather" and w.target==origin.id)
  if g.economy.bank_milli(1).food>bank:break
 c("ordinary travel deposits exact earned load",g.economy.bank_milli(1).food==bank+cargo and g._cargo_amount(w)==0)
 c("deposit never blindly resumes hidden original",not blind_return and w.has("ai_evacuation") and w.state=="idle")
 c("deposit grants no healing",w.hp==hp)
 c("post deposit danger survives checkpoint",roundtrip(g) and g._ai_worker_resource_blocked(origin.pos))
 var alternate=g._spawn("berry",-1,Vector3(-11,0,-7));g._navigation_rebuild();g._update_vision()
 c("alternative is current visible outside old danger",g._visible_to(alternate,1) and not g._ai_worker_resource_blocked(alternate.pos))
 for i in 150:
  step(g)
  if w.state=="gather":break
 c("safe alternative starts normally without forgetting danger",w.state=="gather" and w.target==alternate.id and w.has("ai_evacuation") and w.ai_evacuation.resource==origin.id)
 c("alternative work checkpoint strict roundtrip",roundtrip(g))
 c("alternative ten tick restored continuation is exact",fork_steps(g,10))
 var delivered=g.economy.stats_view(1).delivered.food
 for i in 1400:
  step(g)
  blind_return=blind_return or (w.state=="gather" and w.target==origin.id)
  if g.economy.stats_view(1).delivered.food>delivered:break
 c("alternative completes ordinary gather and next delivery",g.economy.stats_view(1).delivered.food>delivered)
 c("second cycle retains unknown danger",w.has("ai_evacuation") and g._ai_worker_resource_blocked(origin.pos) and not blind_return)
 g._submit("stop",{"ids":[w.id]},1);step(g)
 c("new explicit stop owns worker and cancels memo",not w.has("ai_evacuation") and w.mode=="STOP")
 c("normal economy audit remains valid",g.economy.audit().ok)
 g.free()
 await traffic_mode()
 await blocked_delivery()
 var failed=checks.filter(func(x):return not x.passed).size()
 print(JSON.stringify({"suite":"ai_shelter_delivery_contract","checks":checks,"failed":failed,"scope":"Controlled actors; earned cargo and real hit; normal travel/deposit and safety updates; no hidden-origin return or natural full-match claim."}))
 quit(1 if failed else 0)

func blocked_delivery():
 var g=fresh();await process_frame
 var w=g._spawn("villager",1,Vector3(0,0,-10));var origin=g._spawn("berry",-1,Vector3(0,0,-11))
 g._navigation_rebuild();g._update_vision();g._order(w,"gather",origin.id);step(g,60)
 var foe=g._spawn("spearman",0,w.pos+Vector3(.8,0,0));g._update_vision();g._release_attack(foe,w);step(g)
 for i in 1000:
  step(g)
  if w.has("ai_evacuation") and w.state=="idle" and g._cargo_amount(w)==0:break
 var resource=g._spawn("berry",-1,Vector3(-18,0,-7));g._spawn("scout",1,Vector3(-18,0,-9));g._navigation_rebuild();g._update_vision()
 for i in 600:
  step(g)
  if w.state=="gather" and w.target==resource.id and g._cargo_amount(w)>0:break
 c("blocked branch reaches actual alternative gathering",w.state=="gather" and w.target==resource.id and g._cargo_amount(w)>0 and w.has("ai_evacuation"))
 for x in [-4,-2,0,2,4]:
  for z in [-4,-2,0,2,4]:
   if abs(x)==4 or abs(z)==4:g._spawn("house",0,Vector3(-10+x,0,-10+z))
 g._navigation_rebuild();g._update_vision()
 c("controlled depot enclosure leaves worker start legal",g._static_unit_step_is_free(w,w.pos))
 var before=g.economy.bank_milli(1).food
 for i in 1200:
  step(g)
  if w.path_status in ["NO_PATH","LIMIT_REACHED"]:break
 c("normal delivery search genuinely reaches terminal",w.path_status in ["NO_PATH","LIMIT_REACHED"] and w.path_reason!="")
 c("terminal delivery keeps cargo and danger",w.has("ai_evacuation") and w.state=="idle" and g._cargo_amount(w)>0 and g.economy.bank_milli(1).food==before)
 c("terminal danger checkpoint is strictly valid",roundtrip(g))
 var history=[w.work_epoch,w.path_searches,w.path_failures,w.path_retry_ticks.duplicate(),w.traffic_replans]
 step(g,200)
 c("persistent blockage cannot reset budgets or loop jobs",w.has("ai_evacuation") and history==[w.work_epoch,w.path_searches,w.path_failures,w.path_retry_ticks.duplicate(),w.traffic_replans])
 g.free()

func traffic_mode():
 var g=fresh();await process_frame
 var w=g._spawn("villager",1,Vector3(0,0,-10));var origin=g._spawn("berry",-1,Vector3(0,0,-11))
 g._navigation_rebuild();g._update_vision();g._order(w,"gather",origin.id);step(g,60)
 var foe=g._spawn("spearman",0,w.pos+Vector3(.8,0,0));g._update_vision();var hit=g._release_attack(foe,w);step(g)
 for i in 400:
  step(g)
  if w.state=="idle":break
 var valid=hit.applied and w.state=="idle" and w.has("ai_evacuation") and g._cargo_amount(w)>0
 var cargo=g._cargo_amount(w);var bank=g.economy.bank_milli(1).duplicate(true)
 var searches=w.path_searches;var retry=w.path_retry_ticks.duplicate();var replans=w.traffic_replans
 g._traffic_stop(w,"local_traffic_retry_limit")
 c("traffic stop after real evacuation retains cargo danger and MOVE mode",valid and w.state=="idle" and w.mode=="MOVE" and w.has("ai_evacuation") and w.ai_evacuation.resource==origin.id and g._cargo_amount(w)==cargo and g.economy.bank_milli(1)==bank)
 c("traffic stop does not reset search retry or congestion budget",w.path_status=="LIMIT_REACHED" and w.path_searches==searches and w.path_retry_ticks==retry and w.traffic_replans==replans)
 c("ordinary traffic stop strict capture restore remains valid",roundtrip(g))
 g.free()
