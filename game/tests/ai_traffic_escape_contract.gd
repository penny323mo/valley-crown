extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
func c(name,passed):
 checks.append({"name":name,"passed":bool(passed)})
 if not passed:push_error(name)
func _initialize():call_deferred("run")
func stopped(g,w):
 g._traffic_stop(w,"local_traffic_retry_limit")
 w.traffic_route=true;w.traffic_replans=g.TRAFFIC_MAX_REPLANS;w.traffic_last_replan=g.tick_count-600
func run():
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false
 g._test_reset([{"food":150,"wood":200,"stone":100,"iron":0},{"food":150,"wood":200,"stone":100,"iron":0}]);g.set_process(false);g.ai_enabled=false;await process_frame
 var w=g._first(1,"villager");var berry=g._nearest_resource(w.pos,"food",1)
 g._order(w,"gather",berry.id)
 for i in range(1200):
  g._tick(g.Rules.TICK)
  if g._cargo_amount(w)>0:break
 c("controlled worker earns real gathered cargo",g._cargo_amount(w)>0)
 if g._cargo_amount(w)<=0:g.free();quit(1);return
 var cargo=g._cargo_amount(w);var food=g.economy.bank_milli(1).food
 # Explicit synthetic exhausted-traffic state, not a claimed natural choke.
 # Actual ordinary MOVE has established path identity before traffic stop.
 g._order_move(w,w.pos+Vector3(2,0,0));g._tick(g.Rules.TICK);stopped(g,w);g._update_vision()
 var goal=g._ai_traffic_escape_goal(w)
 c("fixture has nearby observed safe escape",goal!=Vector3.INF)
 if goal==Vector3.INF:g.free();quit(1);return
 c("persistent traffic worker eligible",g._ai_traffic_escape_eligible(w))
 w.traffic_last_replan=g.tick_count-599;c("cooldown refuses early restart",not g._ai_traffic_escape_eligible(w));w.traffic_last_replan=g.tick_count-600
 var oldreason=w.path_reason;w.path_status="NO_PATH";c("static no path never reset",not g._ai_traffic_escape_eligible(w));w.path_status="LIMIT_REACHED"
 w.path_reason="expansion_budget_exhausted";c("general search limit never reset",not g._ai_traffic_escape_eligible(w));w.path_reason=oldreason
 var player=g._first(0,"villager");c("player worker never eligible",not g._ai_traffic_escape_eligible(player))
 # Occupy all otherwise-safe adjacent endpoints with controlled friendly
 # scouts; release one using ordinary MOVE and real ticks, not teleport/kill.
 var blockers=[]
 for offset in [Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0),Vector2i(0,-1)]:
  var cell=g._cell(w.pos)+offset;var p=g._point(cell)
  if not g.work_memory[1].grid.is_point_solid(cell) and g._known_destination_clear(w,p):blockers.append(g._spawn("scout",1,p))
 g._update_vision();g.ai_claimed_workers={};g.commands.clear()
 var oldsearches=w.path_searches
 for i in range(40):g._ai_recover_local_traffic(g._ai_records())
 c("persistent occupied endpoints never submit or search",g.commands.is_empty() and w.path_searches==oldsearches and g._ai_traffic_escape_goal(w)==Vector3.INF)
 var released=false
 for blocker in blockers:
  for offset in [Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0),Vector2i(0,-1)]:
   var destination=g._point(g._cell(blocker.pos)+offset*2)
   if destination.distance_to(w.pos)<2 or g.work_memory[1].grid.is_point_solid(g._cell(destination)) or not g._known_destination_clear(blocker,destination):continue
   g._submit("order",{"ids":[blocker.id],"target":-1,"position":destination},1)
   for i in range(80):g._tick(g.Rules.TICK)
   if g._ai_traffic_escape_goal(w)!=Vector3.INF:released=true;break
  if released:break
 goal=g._ai_traffic_escape_goal(w)
 c("ordinary blocker movement opens recovery endpoint",released and goal!=Vector3.INF and g._cargo_amount(w)==cargo)
 if not released:g.free();quit(1);return
 var before_build_epoch=w.work_epoch;var before_build_status=w.path_status
 g._submit("build",{"builder":w.id,"kind":"house","position":w.pos+Vector3(4,0,0)},1)
 var build_command=g.commands.duplicate(true);g.ai_claimed_workers={};g._ai_recover_local_traffic(g._ai_records())
 c("queued builder-only command blocks recovery before epoch changes",g.commands==build_command and w.work_epoch==before_build_epoch and w.path_status==before_build_status)
 g.commands.clear()
 var epoch=w.work_epoch;var searches=w.path_searches;var retries=w.path_retry_ticks.duplicate();var replans=w.traffic_replans
 g.ai_claimed_workers={};g._ai_recover_local_traffic(g._ai_records())
 c("one recovery command submitted",g.commands.size()==1 and g.commands[0].get("ai_traffic_escape",false))
 var pending=g.commands.duplicate(true)
 g._ai_recover_local_traffic(g._ai_records());c("duplicate think cannot queue another worker command",g.commands==pending)
 var malformed=pending[0].duplicate(true);malformed.retry_gather=true;malformed.command_id="malformed-review"
 g.commands.clear()
 c("mixed marker fixture passes escape preflight",g._ai_traffic_escape_eligible(w) and g._ai_traffic_escape_goal(w)==malformed.position)
 g._execute(malformed)
 g.commands=pending.duplicate(true)
 # _execute records processed sequence for any attempted dispatch. Compare
 # actor and bank, not command processor bookkeeping.
 c("rejected mixed marker keeps worker terminal and budget",w.path_status=="LIMIT_REACHED" and w.work_epoch==epoch and w.traffic_replans==replans and w.path_searches==searches and w.path_retry_ticks==retries and g._cargo_amount(w)==cargo)
 var captured=Codec.capture_result(g)
 c("pending recovery captures with existing schema",captured.ok)
 if not captured.ok:print(captured);g.free();quit(1);return
 var encoded=Codec.encode(captured.data,g.Rules.BUILD_ID);var decoded=Codec.decode(encoded.bytes,g.Rules.BUILD_ID)
 c("pending recovery strict encode decode",encoded.ok and decoded.ok)
 var bank=g.economy.bank_milli(1).duplicate(true)
 g._tick(g.Rules.TICK)
 print("BUDGET_DIAG "+str({"cargo":[cargo,g._cargo_amount(w)],"bank":[bank,g.economy.bank_milli(1)],"retry":[retries,w.path_retry_ticks],"replans":[replans,w.traffic_replans]}))
 c("execution preserves cargo bank and retry history",g._cargo_amount(w)==cargo and g.economy.bank_milli(1)==bank and w.path_retry_ticks.slice(0,retries.size())==retries and w.traffic_replans==replans)
 c("execution uses new ordinary move epoch",w.work_epoch==epoch+1 and w.state=="move")
 var after=Codec.capture_result(g)
 c("executed recovery captures",after.ok)
 c("restore pending recovery succeeds",Restore.apply(g,decoded.data))
 g._toggle_pause();w=g._get_entity(w.id);g._tick(g.Rules.TICK)
 c("restored pending recovery executes same authority",Codec.capture_result(g).data==after.data)
 var origin=w.pos
 for i in range(80):g._tick(g.Rules.TICK)
 c("real ticks move worker to escape endpoint",w.pos.distance_to(origin)>0.2 and w.pos.distance_to(goal)<0.2)
 # Ordinary return-cargo command only after actual movement; no injected bank.
 var home=g._first(1,"town_center")
 g._submit("order",{"ids":[w.id],"target":home.id,"position":home.pos},1)
 for i in range(1400):
  g._tick(g.Rules.TICK)
  if g.economy.bank_milli(1).food>=food+cargo:break
 c("real travel deposits preserved earned cargo",g.economy.bank_milli(1).food>=food+cargo)
 # Stale queued intent must not overwrite a later ordinary job/epoch.
 stopped(g,w);g._update_vision();g.ai_claimed_workers={};g.commands.clear();g._ai_recover_local_traffic(g._ai_records())
 if not g.commands.is_empty():
  var stale=g.commands[0].duplicate(true);g.commands.clear();g._order_move(w,w.pos+Vector3(0,0,2));var current=w.work_epoch;var destination=w.dest;g._execute(stale)
  c("stale epoch leaves newer command untouched",w.work_epoch==current and w.dest==destination)
 else:c("stale epoch leaves newer command untouched",false)
 stopped(g,w);g._update_vision();g.commands.clear();g.ai_claimed_workers={}
 g._ai_update()
 var recovery_commands=g.commands.filter(func(x):return w.id in x.get("ids",[]))
 c("full AI think reserves recovery worker without overwriting",recovery_commands.size()==1 and recovery_commands[0].get("ai_traffic_escape",false))
 g._tick(g.Rules.TICK)
 c("full AI submitted recovery executes ordinary move",w.state=="move" and w.path_status not in ["LIMIT_REACHED","NO_PATH"])
 c("all ordinary economy audit conserved",g.economy.audit().ok)
 var failed=checks.filter(func(x):return not x.passed).size()
 print(JSON.stringify({"suite":"ai_traffic_escape_contract","checks":checks,"failed":failed,"scope":"Controlled exhausted traffic fixture, ordinary gathered cargo, native move/deposit and same-build pending checkpoint; not old-match cross-version recovery or natural victory."}));g.free();quit(1 if failed else 0)
