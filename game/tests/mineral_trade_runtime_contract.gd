extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func fresh():
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="survival";root.add_child(g);g.set_process(false);g.test_mode=true
 # Explicit controlled stocks for transaction boundaries only; natural journey is separate.
 var stock={"food":500,"wood":500,"iron":500,"stone":500};g._test_reset([stock,stock.duplicate(true)]);g.set_process(false)
 return g
func _initialize():call_deferred("run")
func run():
 for source in ["iron","stone"]:
  var g=fresh();await process_frame;var keep=g._first(0,"town_center");var population=g._population(0)
  var before=g.economy.bank_milli(0).duplicate(true)
  g._submit("trade",{"building":keep.id,"from":source,"to":"food"})
  var pending=Codec.capture_result(g)
  check(source+" pending command strict capture",pending.ok)
  if not pending.ok:g.free();finish();return
  var enc=Codec.encode(pending.data,g.Rules.BUILD_ID);var dec=Codec.decode(enc.get("bytes",PackedByteArray()),g.Rules.BUILD_ID)
  check(source+" exact pending transport and wrong build rejected",enc.ok and dec.ok and dec.data==pending.data and not Codec.decode(enc.bytes,"different-build").ok)
  var other=fresh();await process_frame
  check(source+" pending command restore",Restore.apply(other,dec.data));other._toggle_pause()
  g._tick(g.Rules.TICK);other._tick(other.Rules.TICK);g._update_hud();other._update_hud()
  check(source+" pending execution full authority equal",Codec.capture_result(g).data==Codec.capture_result(other).data)
  other.free()
  var receipt=keep.queue[0].receipt_id
  check(source+" exact debit and no immediate credit or population",g.economy.bank_milli(0)[source]==before[source]-100000 and g.economy.bank_milli(0).food==before.food and g._population(0)==population)
  for i in 149:g._tick(g.Rules.TICK)
  g._update_hud();var saved=Codec.capture_result(g)
  check(source+" started strict capture",saved.ok)
  if not saved.ok:g.free();finish();return
  other=fresh();await process_frame;check(source+" started restores",Restore.apply(other,saved.data));other._toggle_pause()
  for i in 149:g._tick(g.Rules.TICK);other._tick(other.Rules.TICK)
  check(source+" 299 ticks still no output",g.economy.bank_milli(0).food==before.food and keep.queue.size()==1)
  g._tick(g.Rules.TICK);other._tick(other.Rules.TICK);g._update_hud();other._update_hud()
  check(source+" tick300 completed and full continuation equal",g.economy.bank_milli(0).food==before.food+60000 and keep.queue.is_empty() and Codec.capture_result(g).data==Codec.capture_result(other).data)
  var done=g.economy.snapshot()
  check(source+" alternate completion id cannot credit twice",not g.economy.complete_trade("duplicate-new-id",receipt,0).applied and g.economy.snapshot().banks==done.banks and g.economy.snapshot().stats==done.stats and g.economy.snapshot().receipts==done.receipts)
  var completed=Codec.capture_result(g)
  check(source+" completed strict capture",completed.ok)
  other.free();other=fresh();await process_frame;check(source+" completed restore",Restore.apply(other,completed.data));other._toggle_pause()
  for i in 2:other._tick(other.Rules.TICK)
  check(source+" completed restore no repeat credit",other.economy.bank_milli(0)==g.economy.bank_milli(0) and other.economy.audit().ok)
  other.free();g.free()
  for stage in ["unstarted","started","destroyed"]:
   g=fresh();await process_frame;keep=g._first(0,"town_center")
   check(source+" "+stage+" ordinary enqueue",g._enqueue_trade(keep.id,source,"food",0))
   var item=keep.queue[0].duplicate(true)
   if stage!="unstarted":g._tick(g.Rules.TICK)
   if stage=="destroyed":g._kill(keep)
   else:g._submit("cancel_queue_item",{"building":keep.id,"queue_id":item.queue_id,"expected_refund":g.economy.quote_refund(item.receipt_id,0)});g._tick(g.Rules.TICK)
   check(source+" "+stage+" precise refund and no output",g.economy.bank_milli(0)[source]==({"unstarted":500000,"started":475000,"destroyed":400000}[stage]) and g.economy.bank_milli(0).food==500000 and g.economy.audit().ok)
   g.free()
 finish()
func finish():
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"mineral_trade_runtime_contract","checks":checks,"failed":failed,"scope":"Controlled starting stock survival fixture, ordinary trade commands/ticks, both new recipes full-state same-build restore; natural gathering tested separately"}));quit(1 if failed else 0)
