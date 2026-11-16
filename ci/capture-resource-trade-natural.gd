extends SceneTree
var g
var checks=[]
var shots=[]
var errors=[]
var proof={"scope":"Ordinary survival scenario with preplaced age and troops; initial resources pay three villagers, a fixed trade and a fourth villager. No resource, HP, unit position, time or sight mutation. Trade output is not harvesting."}
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func workers():
 var ids=[]
 for r in g.faction_views[0].records().values():
  if r.get("owned",false) and r.get("alive",false) and r.get("kind","")=="villager":ids.append(r.id)
 return ids
func shot(label,keep):
 g._select([keep.id]);g.camera_focus=keep.pos;g.camera_zoom=17;g._camera_update();g._update_visuals(0);g._update_hud()
 if label=="trade-in-progress":g._open_trade_panel(keep.id)
 shots.append({"stage":label,"tick":g.tick_count,"bank":g.economy.bank_milli(0)})
 if DisplayServer.get_name()=="headless":return
 for i in 4:await process_frame
 # Scroll the real panel, do not resize runtime UI or imply all four recipes fit.
 if label=="trade-in-progress":
  g.context_details_scroll.ensure_control_visible(g.trade_buttons.trade_wood_food)
  for i in 4:await process_frame
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image()
 var error=ERR_INVALID_DATA if image==null or image.is_empty() else image.save_png("/tmp/capture/resource-trade-"+label+".png")
 if error!=OK:errors.append(error)
func _initialize():call_deferred("run")
func run():
 DirAccess.make_dir_recursive_absolute("/tmp/capture");root.size=Vector2i(640,360)
 g=load("res://main.tscn").instantiate();g.skirmish_mode="survival";g.history_path="/tmp/resource-trade-history-"+str(Time.get_ticks_usec())
 root.add_child(g);g.set_process(false);g.test_mode=true;await process_frame
 var keep=g._first(0,"town_center");var initial=workers();proof.initial_bank=g.economy.bank_milli(0);proof.initial_workers=initial
 var delivered_before=g.economy.snapshot().stats[0].delivered.duplicate(true)
 for i in 3:g._submit("train",{"building":keep.id,"kind":"villager"})
 var paid=false;var started=false;var completed=false;var fourth=false;var finished=false;var receipt="";var start=Time.get_ticks_msec()
 for i in 2500:
  if g.game_over or Time.get_ticks_msec()-start>285000:break
  g._tick(g.Rules.TICK)
  if not paid and g.economy.bank_milli(0).food==0 and keep.queue.size()==3:
   paid=true;proof.food_empty_tick=g.tick_count;await shot("food-empty",keep)
   g._submit("trade",{"building":keep.id,"from":"wood","to":"food"})
  for item in keep.queue:
   if item.get("trade",false):receipt=item.receipt_id
  if not keep.queue.is_empty() and keep.queue[0].get("trade",false) and keep.queue[0].started and not started:
   started=true;proof.trade_start_tick=g.tick_count;await shot("trade-in-progress",keep)
  if not receipt.is_empty() and g.economy.receipt_view(receipt).get("state","")=="fulfilled" and not completed:
   completed=true;proof.trade_complete_tick=g.tick_count;proof.bank_after_trade=g.economy.bank_milli(0);await shot("trade-received",keep)
   g._submit("train",{"building":keep.id,"kind":"villager"});fourth=true
  if fourth and workers().size()==initial.size()+4:
   finished=true;proof.fourth_birth_tick=g.tick_count;await shot("new-villager",keep);break
 proof.ticks=g.tick_count;proof.elapsed_ms=Time.get_ticks_msec()-start;proof.trade_receipt=g.economy.receipt_view(receipt);proof.receipt_id=receipt;proof.final_bank=g.economy.bank_milli(0)
 proof.audit=g.economy.audit();proof.stages=shots;proof.rendered=DisplayServer.get_name()!="headless";proof.final_workers=workers()
 check("uses original survival stocks",proof.initial_bank=={"food":150000,"wood":200000,"stone":100000,"iron":0})
 check("three ordinary paid villagers consume initial food",paid)
 check("trade runs behind those ordinary production orders",started and proof.trade_start_tick>=901)
 check("fifteen second trade completes once",completed and proof.trade_complete_tick-proof.trade_start_tick==299)
 check("trade receives sixty food for one hundred wood",completed and proof.bank_after_trade=={"food":60000,"wood":100000,"stone":100000,"iron":0})
 check("trade receipt is fulfilled",proof.trade_receipt.get("state","")=="fulfilled" and proof.trade_receipt.get("purpose","")=="trade")
 check("trade food pays fourth actual villager",finished and proof.final_workers.size()==initial.size()+4)
 check("final bank matches all five paid orders",proof.final_bank=={"food":10000,"wood":100000,"stone":100000,"iron":0})
 check("trade never increments delivery objective",g.economy.snapshot().stats[0].delivered==delivered_before)
 check("economy audit remains clean",proof.audit.get("ok",false))
 check("test mode and isolated history remain untouched",g.test_mode and not FileAccess.file_exists(g.history_path))
 check("bounded actual scenario completes",finished and g.tick_count<=2500 and proof.elapsed_ms<=285000)
 check("four real capture stages succeed or explicitly headless",shots.size()==4 and errors.is_empty())
 var failed=checks.filter(func(c):return not c.passed).size()
 var report={"suite":"resource_trade_natural_journey","checks":checks,"failed":failed,"scope":proof.scope}
 for pair in [["resource-trade-natural-proof.json",proof],["resource-trade-natural-contract.json",report]]:
  var f=FileAccess.open("/tmp/capture/"+pair[0],FileAccess.WRITE)
  if f==null:quit(1);return
  f.store_string(JSON.stringify(pair[1]));f.close()
 print("RESOURCE_TRADE_PROOF "+JSON.stringify(proof));print(JSON.stringify(report));quit(1 if failed else 0)
