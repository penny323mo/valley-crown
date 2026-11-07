extends SceneTree
# Controlled observed-geometry reconstruction. NOT a restored/continuous match.
# No production edits. Initial buildings/units/resources are unpaid setup;
# fresh zero-cargo economy, full HP, STOP non-targets, omitted nearby enemies,
# distant synthetic enemy keep, AI off. Only the tested queue is really paid.
# After ordinary training executes once, remaining_ticks=0 is a disclosed
# readiness acceleration. Thereafter ONLY normal ticks and one ordinary move.
const EXPECTED_BUILD = "vc-c09af531eecf"
const TOTAL_TICKS = 221
const MOVE_AT = 61
const LAYOUT = [[0,"town_center",0,[-25.0,0.0,24.0]],[1,"villager",0,[-28.20896,0.0,25.71745]],[2,"villager",0,[-29.11153,0.0,26.48806]],[3,"villager",0,[-28.41,0.0,26.50091]],[4,"villager",0,[-29.4,0.0,27.5]],[5,"villager",0,[-26.5,0.0,19.2]],[6,"scout",0,[-20.32118,0.0,22.67882]],[7,"oak",-1,[-31.0,0.0,17.0]],[8,"pine",-1,[-29.5,0.0,17.0]],[9,"pine",-1,[-28.0,0.0,17.0]],[10,"oak",-1,[-31.0,0.0,18.5]],[13,"oak",-1,[-31.0,0.0,20.0]],[14,"oak",-1,[-19.0,0.0,15.0]],[15,"pine",-1,[-17.5,0.0,15.0]],[16,"pine",-1,[-16.0,0.0,15.0]],[17,"oak",-1,[-19.0,0.0,16.5]],[18,"pine",-1,[-17.5,0.0,16.5]],[19,"pine",-1,[-16.0,0.0,16.5]],[20,"oak",-1,[-19.0,0.0,18.0]],[21,"berry",-1,[-31.0,0.0,25.0]],[22,"berry",-1,[-29.5,0.0,25.0]],[23,"berry",-1,[-31.0,0.0,26.5]],[25,"berry",-1,[-31.0,0.0,28.0]],[78,"barracks",0,[-28.5,0.0,23.5]],[79,"villager",0,[-19.6,0.0,19.5]],[85,"spearman",0,[-30.5,0.0,21.5]],[86,"spearman",0,[-30.5,0.0,22.5]],[88,"spearman",0,[-30.5,0.0,23.5]],[90,"house",0,[-25.0,0.0,28.0]],[94,"spearman",0,[-30.5,0.0,24.5]],[95,"spearman",0,[-29.5,0.0,21.5]],[97,"spearman",0,[-28.5,0.0,21.5]],[99,"spearman",0,[-27.5,0.0,21.5]],[101,"spearman",0,[-27.5,0.0,25.5]],[103,"house",0,[-21.0,0.0,28.0]],[107,"spearman",0,[-26.5,0.0,21.5]]]
var g
var checks=[]
var cases=[]
var ids={}
var submitted=[]
func _initialize(): call_deferred("run")
func check(name,ok): checks.append({"name":name,"pass":bool(ok)})
func xyz(p): return [p.x,p.y,p.z]
func setup():
 g._test_reset()
 # Explicit reconstruction boundary, never a command/replay claim.
 for e in g.entities: e.node.queue_free()
 g.entities.clear(); g.next_id=0; ids.clear()
 g.work_memory=[g.WorkMemory.new(),g.WorkMemory.new()]
 g.faction_views=[g.FactionView.new(),g.FactionView.new()]
 for team in 2:
  g.visible_cells[team].fill(0); g.explored_cells[team].fill(0)
 g._reset_economy(g.INITIAL_STOCKS)
 for row in LAYOUT:
  var e=g._spawn(row[1],int(row[2]),Vector3(row[3][0],row[3][1],row[3][2]))
  ids[int(row[0])]=e.id
  if e.category=="unit": g._set_stance(e,"STOP")
 # Keeps the normal end checker active without a nearby combatant.
 g._spawn("town_center",1,g.MapRoutes.home(1))
 g.spawn_availability_polls=0; g.spawn_candidate_checks=0
 g._navigation_rebuild(); g._update_vision(); g._publish_faction_views()
 submitted=[]
func issue(type,data):
 g._submit(type,data,0)
 var copy=g.commands.back().duplicate(true)
 if copy.has("position"): copy.position=xyz(copy.position)
 submitted.append(copy)
func fixed_state(e): return {"id":e.id,"kind":e.kind,"team":e.team,"pos":xyz(e.pos),"alive":e.alive,"hp":e.hp}
func clearance():
 var ok=true
 var minimum=INF
 var units=[]
 for e in g.entities:
  if e.alive and e.category=="unit":
   units.append(e)
   if not g._static_unit_step_is_free(e,e.pos): ok=false
 for i in units.size():
  for j in range(i+1,units.size()):
   var distance=units[i].pos.distance_to(units[j].pos)
   minimum=minf(minimum,distance)
   if distance<units[i].radius+units[j].radius-0.000001: ok=false
 return {"ok":ok,"minimum_unit_distance":minimum}
func free_exits(b):
 var result=[]
 for cell in g._perimeter_cells(b):
  if g.navigation.is_point_solid(cell): continue
  var point=g._point(cell); var blocked=false
  for unit in g.entities:
   if unit.alive and unit.category=="unit" and unit.pos.distance_to(point)<0.7: blocked=true; break
  if not blocked: result.append([cell.x,cell.y])
 return result
func run_case(moving):
 setup()
 var name="move" if moving else "control"
 var b=g._get_entity(ids[78]); var mover=g._get_entity(ids[85])
 var fixed=[]
 for e in g.entities:
  if e.id!=mover.id: fixed.append(fixed_state(e))
 var initial_count=g.entities.size(); var initial_live=g._population(0,false)
 var initial_bank=g.economy.bank_milli(0)
 var initial={"entities":initial_count,"live":initial_live,"capacity":g._capacity(0),"bank":initial_bank,"mover":fixed_state(mover),"producer":b.id,"id_map":ids.duplicate(),"free_exits":free_exits(b),"clearance":clearance()}
 check(name+" reconstructed premise",initial_count==37 and initial_live==16 and g._capacity(0)==20 and free_exits(b).is_empty() and clearance().ok and xyz(mover.pos)==[-30.5,0.0,21.5] and g.economy.audit().ok)
 issue("train",{"building":b.id,"kind":"spearman","command_id":name+"-train"})
 g._tick(g.Rules.TICK)
 check(name+" ordinary paid training",b.queue.size()==1 and g.economy.bank_milli(0)=={"food":100000,"wood":180000} and g._population(0)==17 and g.trained_total[0]==0)
 if b.queue.size()!=1: return
 var receipt=b.queue[0].receipt_id; var queue_id=b.queue[0].queue_id
 var acceleration={"tick":g.tick_count,"before":b.queue[0].remaining_ticks,"after":0}
 b.queue[0].remaining_ticks=0
 var paid_bank=g.economy.bank_milli(0)
 var trace=[]; var unchanged=true; var geometry=true; var audits=true; var frozen_bank=true; var ticks=true; var reserved=true
 var birth_tick=-1; var newborn_id=-1; var transition_count=0; var previous_state="open"; var blocked_before=true
 for step in range(2,TOTAL_TICKS+1):
  if moving and g.tick_count==MOVE_AT:
   issue("order",{"ids":[mover.id],"target":-1,"position":Vector3(-31.5,0,21.5),"command_id":"move-clear-exit"})
  g._tick(g.Rules.TICK)
  ticks=ticks and g.tick_count==step and not g.paused and not g.game_over and not g.ai_enabled
  for before in fixed:
   unchanged=unchanged and fixed_state(g._get_entity(before.id))==before
  var clear=clearance(); geometry=geometry and clear.ok
  audits=audits and g.economy.audit().ok
  frozen_bank=frozen_bank and g.economy.bank_milli(0)==paid_bank
  reserved=reserved and g._population(0)==17
  var state=g.economy.receipt_view(receipt).state
  if state!=previous_state: transition_count+=1; previous_state=state
  if not g.spawn_commit_order.is_empty() and birth_tick<0:
   birth_tick=g.tick_count; newborn_id=g.entities.back().id
  var newborn={}
  if newborn_id>=0:
   var n=g._get_entity(newborn_id)
   newborn={"id":n.id,"pos":xyz(n.pos),"alive":n.alive,"kind":n.kind,"team":n.team}
  if step<=MOVE_AT: blocked_before=blocked_before and b.queue.size()==1 and state=="open" and g.spawn_commit_order.is_empty() and free_exits(b).is_empty()
  trace.append({"tick":g.tick_count,"mover":xyz(mover.pos),"mover_state":mover.state,"path_status":mover.get("path_status",""),"path_reason":mover.get("path_reason",""),"queue":b.queue.duplicate(true),"receipt_state":state,"commits":g.spawn_commit_order.size(),"live":g._population(0,false),"reserved_population":g._population(0),"polls":g.spawn_availability_polls,"candidate_checks":g.spawn_candidate_checks,"newborn":newborn,"geometry":clear.ok,"minimum_unit_distance":clear.minimum_unit_distance})
 check(name+" blocked sixty ticks",blocked_before)
 check(name+" ordinary tick bounds",ticks and g.tick_count==TOTAL_TICKS)
 check(name+" untouched geometry and health",unchanged)
 check(name+" no overlaps every tick",geometry)
 check(name+" conserved paid bank",frozen_bank and audits and reserved and g.economy_sequence==1)
 check(name+" one receipt only",g.economy.snapshot().receipts.size()==1 and g.economy.receipt_view(receipt).paid_milli=={"food":50000,"wood":20000})
 if moving:
  check(name+" ordinary move completed",mover.pos.distance_to(Vector3(-31.5,0,21.5))<0.001 and mover.state=="idle" and g.processed_command_ids.has("0:move-clear-exit"))
  check(name+" one fulfillment and birth",transition_count==1 and previous_state=="fulfilled" and birth_tick>MOVE_AT and birth_tick<=181 and g.spawn_commit_order.size()==1 and g.trained_total[0]==1 and b.queue.is_empty() and g.entities.size()==initial_count+1 and g._population(0,false)==17)
  check(name+" original receipt queue committed",g.spawn_commit_order.size()==1 and g.spawn_commit_order[0].queue==queue_id and g.spawn_commit_order[0].building==b.id and g.economy.snapshot().transactions.has("fulfilled:"+receipt))
  check(name+" freed exit used safely",newborn_id>=0 and g._get_entity(newborn_id).pos==Vector3(-30.5,0,21.5) and g._get_entity(newborn_id).kind=="spearman" and g._get_entity(newborn_id).team==0)
  check(name+" forty tick duplicate guard",birth_tick>0 and TOTAL_TICKS-birth_tick>=40 and g.spawn_commit_order.size()==1 and g.economy.snapshot().transactions.size()==2)
 else:
  check(name+" no move no fulfillment",transition_count==0 and previous_state=="open" and birth_tick==-1 and g.spawn_commit_order.is_empty() and g.trained_total[0]==0 and b.queue.size()==1 and g.entities.size()==initial_count and g._population(0,false)==16 and mover.pos==Vector3(-30.5,0,21.5))
  check(name+" retry budget retained",g.spawn_availability_polls==11 and g.spawn_candidate_checks==176 and b.queue[0].receipt_id==receipt and b.queue[0].queue_id==queue_id and b.queue[0].remaining_ticks==0 and g.economy.snapshot().transactions.size()==1)
 cases.append({"name":name,"initial":initial,"acceleration":acceleration,"receipt_id":receipt,"queue_id":queue_id,"commands":submitted.duplicate(true),"trace":trace,"birth_tick":birth_tick,"final_receipt":g.economy.receipt_view(receipt),"final_bank":g.economy.bank_milli(0),"final_commits":g.spawn_commit_order.duplicate(true),"final_audit":g.economy.audit(),"final_transactions":g.economy.snapshot().transactions,"fixed_final_unchanged":unchanged})
func run():
 var args=OS.get_cmdline_user_args()
 if args.size()!=1 or not args[0].is_absolute_path(): quit(2); return
 g=load("res://main.tscn").instantiate(); root.add_child(g); g.test_mode=true; g.set_process(false)
 check("expected unchanged build",g.Rules.BUILD_ID==EXPECTED_BUILD)
 if g.Rules.BUILD_ID==EXPECTED_BUILD:
  run_case(false); run_case(true)
 var failed=checks.filter(func(c): return not c.pass).size()
 var script=get_script().resource_path
 var report={"schema":"production-exit-reconstruction-v1","scope":"Controlled observed-geometry reconstruction, not continuous replay or natural setup; no visual/phone acceptance.","build":g.Rules.BUILD_ID,"game_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"manifest_sha256":FileAccess.get_sha256("res://reports/build-manifest.json"),"contract_sha256":FileAccess.get_sha256(script),"source_lock_sha256":FileAccess.get_sha256(script.get_base_dir().path_join("source_lock.json")),"engine":Engine.get_version_info(),"total_ticks_per_case":TOTAL_TICKS,"checks":checks,"cases":cases,"failed":failed,"completed":cases.size()==2}
 var output=FileAccess.open(args[0],FileAccess.WRITE)
 if output==null: quit(2); return
 output.store_string(JSON.stringify(report)); output.close()
 print("PRODUCTION_EXIT_CONTRACT "+JSON.stringify({"checks":checks.size(),"failed":failed,"completed":cases.size()==2}))
 quit(0 if failed==0 and cases.size()==2 else 1)
