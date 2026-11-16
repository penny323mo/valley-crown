extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func make_game(mode):
 var g=load("res://main.tscn").instantiate();g.skirmish_mode=mode;root.add_child(g);g.set_process(false);g.test_mode=true
 return g
func run():
 await standard_case()
 await combat_case()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"checkpoint_continuation_contract","checks":checks,"failed":failed,"scope":"Exact-build private snapshot restore into disposable fresh game; ordinary AI/economy/combat continuation, not filesystem or browser persistence acceptance"}))
 quit(0 if failed==0 else 1)
func standard_case():
 var g=make_game("standard");await process_frame
 var workers=g.entities.filter(func(e):return e.alive and e.team==0 and e.kind=="villager")
 var worker=workers[0];var builder=workers[1];var berry=g._first(-1,"berry")
 g._order(worker,"gather",berry.id)
 for i in 400:g._tick(.05)
 check("standard AI progresses for four hundred ordinary ticks",g.tick_count==400 and g.ai_enabled and g.ai_opening_assigned)
 check("ordinary worker gathering extracts food before checkpoint",g.economy.stats_view(0).extracted.food>0)
 var point=Vector3.INF
 for z in range(-6,7):
  for x in range(-6,7):
   var p=g._snap_build_position("house",g.MapRoutes.PLAYER_HOME+Vector3(x,0,z))
   if g._placement_reason("house",p,0,builder.id).is_empty():point=p;break
  if point!=Vector3.INF:break
 check("checkpoint construction uses legally available ground",point!=Vector3.INF)
 if point==Vector3.INF:g.free();return
 var site=g._place_building("house",point,builder.id,0)
 check("unfinished house has ordinary paid construction receipt",not site.is_empty() and not site.built and not site.cost_receipt_id.is_empty())
 if site.is_empty():g.free();return
 var keep=g._first(0,"town_center")
 g._submit("train",{"building":keep.id,"kind":"villager","command_id":"checkpoint-paid-train"},0)
 g._tick(.05)
 check("paid training remains in progress at checkpoint",keep.queue.size()==1 and keep.queue[0].remaining_ticks>0)
 var captured=Codec.capture_result(g)
 check("standard midgame snapshot validates",captured.ok)
 if not captured.ok:print(captured);g.free();return
 var data=captured.data;var encoded=Codec.encode(data,g.Rules.BUILD_ID);var decoded=Codec.decode(encoded.get("bytes",PackedByteArray()),g.Rules.BUILD_ID)
 check("standard checkpoint roundtrip validates",encoded.ok and decoded.ok)
 if not decoded.ok:g.free();return
 var h=make_game("standard");await process_frame
 check("standard checkpoint restores into disposable fresh game",Restore.apply(h,decoded.data))
 check("restored standard authority equals captured boundary",Codec.capture(h)==data)
 check("restored economy passes conservation audit",h.economy.audit().ok)
 check("worker cargo remains exact across restoration",h.economy.worker_view(worker.id)==g.economy.worker_view(worker.id))
 check("unfinished site progress and receipt remain exact",h._get_entity(site.id).build_ticks==site.build_ticks and h._get_entity(site.id).cost_receipt_id==site.cost_receipt_id)
 var bank=h.economy.bank_milli(0).duplicate(true);var queue=h._get_entity(keep.id).queue.duplicate(true)
 var duplicate={"type":"train","team":0,"building":keep.id,"kind":"villager","command_id":"checkpoint-paid-train"}
 h._execute(duplicate);g._execute(duplicate)
 check("processed training command cannot spend twice after restore",h.economy.bank_milli(0)==bank and h._get_entity(keep.id).queue==queue)
 h.paused=false
 for i in 400:g._tick(.05);h._tick(.05)
 var left=Codec.capture(g);var right=Codec.capture(h)
 check("standard AI economy and routes continue identically four hundred ticks",not left.is_empty() and left==right)
 if left!=right:
  for key in left:
   if left[key]!=right.get(key):print("STANDARD_DIFFERENCE ",key)
 check("paid villager naturally completes once on each branch",g.trained_total[0]==1 and h.trained_total[0]==1 and g._get_entity(keep.id).queue.is_empty() and h._get_entity(keep.id).queue.is_empty())
 check("continued economic conservation holds on both branches",g.economy.audit().ok and h.economy.audit().ok)
 g.free();h.free();await process_frame
func combat_case():
 var g=make_game("survival");await process_frame
 for i in 1500:g._tick(.05)
 check("survival reaches real ordinary first wave combat",g.siege_challenge.wave==1 and g.attack_ledger.next_attack_id()>1)
 var captured=Codec.capture_result(g)
 check("active combat checkpoint validates",captured.ok)
 if not captured.ok:print(captured);g.free();return
 var data=captured.data;var encoded=Codec.encode(data,g.Rules.BUILD_ID);var decoded=Codec.decode(encoded.get("bytes",PackedByteArray()),g.Rules.BUILD_ID)
 check("combat checkpoint roundtrip validates",encoded.ok and decoded.ok)
 if not decoded.ok:g.free();return
 var h=make_game("survival");await process_frame
 check("active combat restores into disposable fresh game",Restore.apply(h,decoded.data))
 check("restored combat authority equals captured boundary",Codec.capture(h)==data)
 var event=h.attack_ledger.event(1);var before=h.attack_ledger.snapshot();var replay=h.attack_ledger.replay(event)
 check("settled issued attack remains duplicate without second application",replay.ok and not replay.applied and replay.reason=="DUPLICATE" and h.attack_ledger.snapshot()==before)
 var conflict=event.duplicate(true);conflict.damage+=1
 check("altered issued attack payload remains rejected",not h.attack_ledger.replay(conflict).ok and h.attack_ledger.snapshot()==before)
 h.paused=false
 for i in 200:g._tick(.05);h._tick(.05)
 var left=Codec.capture(g);var right=Codec.capture(h)
 check("combat damage veterancy fog and paths continue identically two hundred ticks",not left.is_empty() and left==right)
 if left!=right:
  for key in left:
   if left[key]!=right.get(key):print("COMBAT_DIFFERENCE ",key)
 g.free();h.free();await process_frame
