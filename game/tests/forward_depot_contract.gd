extends SceneTree
## Focused ledger/placement/isolated menu checks. The natural journey is separate.
const Policy=preload("res://scripts/forward_depot.gd")
const Ledger=preload("res://scripts/economy_ledger.gd")
const Old=preload("res://scripts/skirmish_policy.gd")
const Ordinary=preload("res://scripts/checkpoint_store.gd")
const Extra=preload("res://scripts/expedition_checkpoint_store.gd")
const Auto=preload("res://scripts/auto_checkpoint.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
var checks=[]
func check(name,ok):
 checks.append({"name":name,"passed":bool(ok)})
 if not ok:push_error(name)
func _initialize():call_deferred("run")
func input(root_node,name):
 var item=root_node.get_node_or_null(name)
 if not is_instance_valid(item):return false
 item.pressed.emit()
 return true
func gather(ledger,worker,node,start):
 for i in range(start,start+300):ledger.gather_tick(worker,node,i)
 return ledger.worker_view(worker).cargo_revision
func run():
 var e=Ledger.new()
 check("two personal test factions initialized",e.initialize([{"wood":200,"food":200},{"wood":200,"food":200}]).ok)
 e.register_worker(20,0);e.register_worker(21,0);e.register_node(9,"wood",900000);e.register_node(10,"food",900000)
 var d=Policy.new()
 var s={"id":11,"team":0,"kind":"storehouse","alive":true,"built":true,"pos":Vector3(-11,0,16),"cost_receipt_id":"depot-buy"}
 var wrong=s.duplicate(true);wrong.id=12;wrong.pos=Vector3(-17,0,16)
 var home=s.duplicate(true);home.kind="town_center"
 var hostile=s.duplicate(true);hostile.team=1
 var unfinished=s.duplicate(true);unfinished.built=false
 var dead=s.duplicate(true);dead.alive=false
 var free=s.duplicate(true);free.cost_receipt_id=""
 var trade=s.duplicate(true);trade.cost_receipt_id="foo-trade"
 check("initial stocks count zero",d.totals=={"wood":0,"food":0})
 check("free warehouse and unfinished site cannot qualify",not Policy.qualifies(free,e) and not Policy.qualifies(unfinished,e))
 var pay=e.pay("depot-buy",0,{"wood":80},Ledger.REFUND_STARTED)
 check("open payment is not completed depot",pay.applied and not Policy.qualifies(s,e))
 check("completed paid matching warehouse is eligible",e.fulfill_cost("finish",pay.receipt_id,0).applied and Policy.qualifies(s,e))
 check("other category, outside, dead, foreign and nonreceipt excluded",[wrong,home,hostile,dead,free,trade].all(func(a):return not Policy.qualifies(a,e)))
 check("zone is finite inclusive snapped center",Policy.in_zone(Vector3(-16,0,12)) and Policy.in_zone(Vector3(-7,0,18)) and not Policy.in_zone(Vector3(-16.01,0,12)) and not Policy.in_zone(Vector3.INF))
 var rev=gather(e,20,9,0)
 var r=e.deposit("bring-actual-wood",20,rev)
 check("ordinary receipt only credit as exact accepted destination",r.applied and r.amount_milli==10000 and not d.observe(301,home,e,r) and not d.observe(301,wrong,e,r) and d.observe(301,s,e,r) and d.totals.wood==10000)
 var snapshot=e.snapshot()
 check("same applied receipt object can never double credit",not d.observe(301,s,e,r) and d.totals.wood==10000 and d.delivery_count==1)
 var replay=e.deposit("bring-actual-wood",20,rev)
 check("ledger replay reports no commit and adds no credit",replay.replayed and not replay.applied and not d.observe(302,s,e,replay))
 check("replay and tracker never change ledger",snapshot==e.snapshot())
 var new_rev=gather(e,21,10,190)
 var f=e.deposit("bring-actual-food",21,new_rev)
 check("real food contributes only to food",d.observe(491,s,e,f) and d.totals=={"wood":10000,"food":10000})
 var invalid=f.duplicate(true);invalid.resource_type="stone";invalid.cargo_revision+=10
 check("non-goal mineral cannot credit",not d.observe(492,s,e,invalid))
 var fail=e.deposit("stale",21,new_rev)
 check("stale cargo and rejected receipt cannot score",not fail.applied and not d.observe(492,s,e,fail))
 for counts in [11,7]:
  var worker_id=20 if counts==11 else 21
  var node_id=9 if counts==11 else 10
  for i in counts:
   var start=1000+i*320
   var x=gather(e,worker_id,node_id,start)
   var step=e.deposit("next-%d-%d"%[worker_id,i],worker_id,x)
   d.observe(start+301,s,e,step)
 check("only real qualifying credits meet exact quotas",d.totals==Policy.GOALS and d.complete([s],e))
 check("lost depot retains credits but cannot win itself",not d.complete([dead,wrong,home],e) and d.totals==Policy.GOALS)
 check("actual combined threshold is compatible with conserved balances",e.audit().ok and d.delivery_count==20)
 check("ledger qualified receipt state preserved",e.receipt_view(pay.receipt_id).state=="fulfilled")
 var shell=load("res://main_menu.tscn").instantiate()
 root.add_child(shell);await process_frame
 var dir="/tmp/forward-depot-sandbox-"+str(Time.get_ticks_usec())
 DirAccess.make_dir_absolute(dir)
 shell.checkpoint_path=dir+"/ordinary.bin";shell.expedition_checkpoint_path=dir+"/expedition.bin";shell.auto_checkpoint_path=dir+"/auto.bin";shell.campaign_progress_path=dir+"/campaign.json"
 for path in [shell.checkpoint_path,shell.expedition_checkpoint_path,shell.auto_checkpoint_path,shell.campaign_progress_path]:
  var file=FileAccess.open(path,FileAccess.WRITE);file.store_string("isolated baseline fixture");file.close()
 check("mission entry runs ordinary grouped navigation",input(shell.buttons,"StartMatchButton") and input(shell.buttons,"BattleGroup3") and input(shell.buttons,"ChooseBattle_depot") and shell.page=="setup")
 check("briefing explicitly tells only paid forward deposit and no save",shell.selected_mode=="depot" and shell.description.text.contains("起始庫存") and shell.description.text.contains("實際送抵") and shell.description.text.contains("暫不支援存檔"))
 check("ordinary launch pressed",input(shell.buttons,"LaunchMatchButton"))
 for i in 4:await process_frame
 var g=shell.match_node
 g.test_mode=true;g.set_process(false)
 check("new authored match is not campaign nor control/race",g.skirmish_mode=="depot" and g.victory_mode=="conquest" and g.campaign_chapter<0 and shell.BattleSelection.CAMPAIGN==["breach","survival","escort"])
 check("only authored marker appears in depot mode",g.escort_outline.name=="ForwardDepotBoundary" and g.escort_outline_segments.size()==30 and not g.control_point_marker.visible)
 check("ordinary slot rejects before write",not Ordinary.save_slot(g,shell.checkpoint_path).ok)
 check("expedition slot rejects before write",not Extra.save_slot(g,shell.expedition_checkpoint_path).ok)
 check("automatic slot rejects before write",not Auto.save_slot(g,shell.auto_checkpoint_path).ok)
 check("codec does not permit this unsupported mode",not Codec.capture_result(g).ok)
 check("initial scoreboard zero regardless of starting stocks",g.forward_depot.totals=={"wood":0,"food":0} and g.objective_button.text.contains("0/120") and g.economy.bank_milli(0).wood>0)
 g._submit("surrender");g._tick(.05)
 check("actual ordinary surrender is a real loss",g.game_over and g.outcome=="defeat" and g.end_reason=="surrender" and g.end_title.text=="我方投降")
 check("normal terminal replay action exists",input(g.end_actions,"ReplayMatchButton"))
 for i in 4:await process_frame
 var next=shell.match_node
 next.test_mode=true;next.set_process(false)
 check("replay creates fresh same authored mission, counters zero",next!=g and next.skirmish_mode=="depot" and not next.game_over and next.forward_depot.delivery_count==0)
 check("campaign and existing slots are byte-identical",[shell.checkpoint_path,shell.expedition_checkpoint_path,shell.auto_checkpoint_path,shell.campaign_progress_path].all(func(path):return FileAccess.get_file_as_string(path)=="isolated baseline fixture"))
 var font=next.objective_button.get_theme_font("font")
 for dims in [Vector2i(320,568),Vector2i(640,360),Vector2i(844,390)]:
  root.size=dims
  for i in 3:await process_frame
  next._update_hud()
  var button=next.objective_button
  check("mission top controls and count fit "+str(dims),root.get_visible_rect().encloses(button.get_global_rect()) and button.size.y>=44 and Array(button.text.split("\n")).all(func(line):return font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x<=button.size.x-12))
  shell._open_menu();shell._show_page("battle_groups")
  check("new option remains inside actual menu route "+str(dims),input(shell.buttons,"BattleGroup3") and is_instance_valid(shell.buttons.get_node_or_null("ChooseBattle_depot")))
  var entry=shell.buttons.get_node("ChooseBattle_depot")
  var parent=entry.get_parent()
  while is_instance_valid(parent):
   if parent is ScrollContainer:parent.ensure_control_visible(entry);break
   parent=parent.get_parent()
  for i in 4:await process_frame
  var eb=entry.get_global_rect()
  check("new option stays visibly tappable after ordinary scroll "+str(dims),entry.is_visible_in_tree() and eb.size.y>=44 and root.get_visible_rect().encloses(eb))
  shell._resume_match()
  for i in 3:await process_frame
  next.set_process(false);next.test_mode=true
 var n=checks.filter(func(q):return not q.passed).size()
 print(JSON.stringify({"suite":"forward_depot_contract","scope":"Ledger/API and routed menu/loss/replay safety. Separate ordinary played victory required.","checks":checks,"failed":n}))
 shell.queue_free();quit(0 if n==0 else 1)
