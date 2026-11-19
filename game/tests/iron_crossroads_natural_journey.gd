extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
var g
var c=[]
var job=[]
var transits=[]
var crosses={}
var worker={}
var deposits=[]
var ore={}
var warehouse={}
var scout={}
func _initialize():call_deferred("run")
func ck(n,v):
 c.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
 return bool(v)
func ticks(max_ticks,until):
 for i in max_ticks:
  var bank_refer=g.economy.bank_milli(0).iron
  var observed_dropoff=worker.get("target",-1) if worker.get("state","")=="deliver" else -1
  g._tick(g.Rules.TICK)
  if g.economy.bank_milli(0).iron>bank_refer:deposits.append({"tick":g.tick_count,"target":observed_dropoff,"milli":g.economy.bank_milli(0).iron-bank_refer})
  if g.tick_count%10==0:
   for r in g.entities:
    if not r.alive or r.team!=1 or r.category!="unit":continue
    if r.pos.z>=1.0 and absf(r.pos.x)<24 and not crosses.has(r.id):
     crosses[r.id]={"tick":g.tick_count,"unit":r.kind,"mode":r.mode,"position":str(r.pos)}
  if until.call() or g.game_over:return
func current_ore():
 for r in g.faction_views[0].records().values():
  if r.get("category","")=="resource" and r.kind=="iron" and r.pos.x<0 and r.pos.z>0 and absf(r.pos.x)<5 and absf(r.pos.z)<5 and r.get("alive",false) and not r.get("remembered",true):
   return r
 return {}
func run():
 root.size=Vector2i(640,360)
 g=load("res://main.tscn").instantiate();g.layout_id="iron_crossroads";g.skirmish_mode="standard";g.history_path="/tmp/crossroads-journey-private";root.add_child(g);g.set_process(false);g.test_mode=true
 await process_frame
 worker=g._first(0,"villager");scout=g._first(0,"scout")
 var open=g.economy.bank_milli(0).duplicate(true)
 ck("natural standard AI and exact original bank",g.ai_enabled and open=={"food":150000,"wood":200000,"stone":100000,"iron":0})
 ck("forward iron initially unrevealed by spawn",current_ore().is_empty())
 g._submit("order",{"ids":[scout.id],"target":-1,"position":Vector3(-.5,0,6.5)})
 ticks(950,func():return not current_ore().is_empty())
 var public=current_ore()
 if not ck("ordinary scout reveals real central iron by walking through fog",not public.is_empty() and scout.alive):
  finish();return
 ore=g._get_entity(public.id)
 job.append({"phase":"scout_revealed","tick":g.tick_count,"scout":str(scout.pos),"ore":str(ore.pos)})
 # Keep opening safe; supply decision is optional and actually spends wood.
 var plot=Vector3.INF
 for xz in [Vector2(-5.5,7.5),Vector2(-3.5,6.5),Vector2(-.5,6.5),Vector2(2.5,5.5),Vector2(-5.5,5.5)]:
  var p=Vector3(xz.x,0,xz.y)
  if g._placement_reason("storehouse",p,0,worker.id).is_empty():plot=p;break
 if not ck("at least one legal visible forward warehouse investment",plot.is_finite()):
  finish();return
 var before=g.economy.bank_milli(0).wood
 g._submit("build",{"kind":"storehouse","position":plot,"builder":worker.id,"ids":[worker.id]})
 ticks(1400,func():return not g._first(0,"storehouse").is_empty() and g._first(0,"storehouse").built)
 warehouse=g._first(0,"storehouse")
 if not ck("ordinary paid warehouse completed and expenses exact",not warehouse.is_empty() and warehouse.built and g.economy.bank_milli(0).wood==before-80000):
  finish();return
 job.append({"phase":"forward_warehouse_completed","tick":g.tick_count,"plot":str(plot)})
 # Public resource identity only; no external grant or AI disable.
 ck("central deposit still currently observed",not g.faction_views[0].get_record(ore.id).get("remembered",true))
 g._submit("order",{"ids":[worker.id],"target":ore.id,"position":ore.pos})
 ticks(1100,func():return g.economy.bank_milli(0).iron>0)
 ck("actual iron excavated and delivered by own worker",g.economy.bank_milli(0).iron>0 and worker.alive and not g.game_over)
 ck("worker selected the forward warehouse for nearby delivery",deposits.size()==1 and deposits[0].target==warehouse.id and deposits[0].milli>=1000)
 job.append({"phase":"delivered","tick":g.tick_count,"worker":str(worker.pos),"warehouse":str(warehouse.pos),"ore":str(ore.pos),"iron":g.economy.bank_milli(0).iron})
 # Ask the existing opposing AI to handle live pressures, no mutations.
 # Keep the original standard difficulty and watch a modest additional window.
 ticks(900,func():return not crosses.is_empty())
 ck("normal AI actually crossed into player side",not crosses.is_empty())
 ck("ledger remains conserved for both teams",g.economy.audit().ok)
 var archive=Codec.capture_result(g)
 ck("ordinary full capture preserves new battlefield and resources",archive.ok and archive.data.game.layout_id=="iron_crossroads" and Codec.validate(archive.data))
 finish()
func finish():
 var failed=c.filter(func(x):return not x.passed).size()
 print("CROSSROADS_JOURNEY_EVIDENCE "+JSON.stringify({"stage":job,"crosses":crosses,"deposits":deposits,"tick":g.tick_count}))
 print(JSON.stringify({"suite":"iron_crossroads_natural_journey","scope":"Original standard start, fog, orders and AI; bounded scout/actual logistics/AI crossing, not full match or true phone.","checks":c,"failed":failed}))
 g.free();quit(0 if failed==0 else 1)
