extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var g
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func refresh():
 g._update_vision(false);g._publish_faction_views()
func run():
 g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false)
 await process_frame
 var guard=g._first(0,"scout");var ally=g._first(0,"villager")
 guard.pos=Vector3(-4.5,0,4.5);ally.pos=Vector3(3.5,0,4.5);g._set_stance(guard,"STOP");g._set_stance(ally,"STOP");refresh()
 var bank=g.economy.bank_milli(0).duplicate(true);var ally_state=ally.duplicate(true)
 g._submit("escort",{"ids":[guard.id,ally.id,guard.id],"target":ally.id});g._tick(.05)
 check("mixed explicit command assigns only eligible guard",guard.mode=="ESCORT" and guard.escort_target==ally.id and not ally.has("escort_target"))
 check("protectee orders and cargo are not rewritten",ally.state==ally_state.state and ally.target==ally_state.target and g.economy.worker_view(ally.id).cargo_milli==0)
 var origin=guard.pos;var max_queries=0
 for i in 200:
  g._tick(.05);max_queries=maxi(max_queries,g.last_path_queries)
 check("guard follows using real bounded movement",guard.pos.distance_to(origin)>1.0 and guard.mode=="ESCORT")
 check("following respects global path query bound",max_queries<=4)
 check("automatic following has only one initial search",guard.path_initial_searches==1)
 refresh();g._select([guard.id]);g._start_escort_command()
 check("explicit touch action arms ally targeting",g.touch_command and g.unit_command_kind=="escort")
 var pending=g.commands.size()
 check("invalid target keeps targeting and queues nothing",not g._submit_escort_target(-1) and g.touch_command and g.commands.size()==pending)
 g._cancel_mode()
 check("cancel targeting preserves active escort",guard.mode=="ESCORT" and guard.has("escort_target"))
 g.camera_focus=ally.pos;g._camera_update();refresh()
 g._select([guard.id]);g._start_escort_command()
 var screen=g.camera.unproject_position(ally.pos+Vector3(0,0.6,0))
 g._tap(screen,true)
 check("shared touch tap submits explicit escort not ordinary move",not g.touch_command and g.commands.any(func(c):return c.type=="escort" and c.target==ally.id))
 g._tick(.05);refresh();g._select([guard.id])
 var count_before=g.commands.size();g._tap(screen,true)
 check("ordinary friendly tap still selects without escort command",g.selected==[ally.id] and g.commands.size()==count_before)
 g._submit("order",{"ids":[ally.id],"target":-1,"position":ally.pos+Vector3(4,0,0)})
 var guard_before=guard.pos;var initial_before=guard.path_initial_searches+(0 if guard.path_has_attempt else 1)
 for i in 120:g._tick(.05)
 check("escort follows a moving protectee after initial arrival",guard.mode=="ESCORT" and guard.escort_target==ally.id and guard.pos.distance_to(guard_before)>0.5)
 check("follow uses only initial search granted by explicit touch order",guard.path_initial_searches==initial_before)
 var snap=Codec.capture_result(g)
 check("escort snapshot validates",snap.ok)
 if snap.ok:
  var encoded=Codec.encode(snap.data,g.Rules.BUILD_ID);var decoded=Codec.decode(encoded.bytes,g.Rules.BUILD_ID)
  var h=load("res://main.tscn").instantiate();root.add_child(h);h.set_process(false);h.test_mode=true
  await process_frame
  check("escort restores into disposable game",decoded.ok and Restore.apply(h,decoded.data))
  check("exact escort authority retained",Codec.capture(h)==snap.data)
  h.paused=false
  for i in 60:g._tick(.05);h._tick(.05)
  check("escort continues identically after memory restore",Codec.capture(h)==Codec.capture(g))
  h.free()
  var corrupt=snap.data.duplicate(true)
  for e in corrupt.entities:
   if e.id==guard.id:e.escort_target="bad"
  check("malformed optional escort identity rejected",not Codec.validate(corrupt))
 refresh()
 # A separately spawned military enemy uses ordinary damage; controlled HP is explicit.
 var enemy=g._spawn("spearman",1,guard.pos+Vector3(0.8,0,0));enemy.hp=enemy.max_hp;g._set_stance(enemy,"STOP")
 ally.pos=guard.pos+Vector3(0,0,1);guard.escort_next_tick=g.tick_count;guard.cooldown_ticks=0;refresh()
 g._tick(.05)
 var combat=Codec.capture_result(g)
 check("active escort interception snapshot validates",combat.ok and guard.state=="attack" and guard.mode=="ESCORT")
 if combat.ok:
  var h=load("res://main.tscn").instantiate();root.add_child(h);h.set_process(false);h.test_mode=true;await process_frame
  check("active interception restores",Restore.apply(h,combat.data))
  h.paused=false
  for i in 20:g._tick(.05);h._tick(.05)
  check("interception continuation is exact",Codec.capture(g)==Codec.capture(h))
  h.free()
 enemy.hp=1;guard.cooldown_ticks=0
 for i in 30:
  g._tick(.05)
  if not enemy.alive:break
 check("guard intercepts actual visible military threat",not enemy.alive and g.attack_ledger.next_attack_id()>1)
 check("automatic combat retains protectee intent",guard.mode=="ESCORT" and guard.get("escort_target",-1)==ally.id)
 g._submit("stop",{"ids":[guard.id]});g._tick(.05)
 check("explicit stop retires escort",guard.mode=="STOP" and not guard.has("escort_target"))
 g._order_escort([guard.id],ally.id,0);guard.path_status=g.BoundedPath.LIMIT_REACHED
 g._update_escorts()
 check("terminal path never automatically resurrects",guard.mode=="STOP" and not guard.has("escort_target"))
 g._order_escort([guard.id],ally.id,0);g._traffic_stop(guard,"test_stop");g._update_escorts()
 check("traffic stop cannot resurrect via stale escort field",guard.mode=="STOP" and not guard.has("escort_target"))
 g._order_escort([guard.id],ally.id,0);g._order_move(guard,guard.pos+Vector3(2,0,0))
 check("normal move overrides escort",not guard.has("escort_target") and guard.mode=="MOVE")
 g._order_escort([guard.id],ally.id,0);g._kill(ally);refresh();guard.escort_next_tick=g.tick_count;g._update_escorts()
 check("observed protectee death stops escort safely",guard.mode=="STOP" and not guard.has("escort_target"))
 check("escort never alters resources",g.economy.bank_milli(0)==bank and g.economy.audit().ok)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"escort_integration_contract","checks":checks,"failed":failed,"scope":"Controlled native commands and memory-only snapshots. No player saves or browser persistence."}))
 g.free();quit(1 if failed else 0)
