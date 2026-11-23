# QA only: no state injection or generated scenes. See scope in native report.
extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var checks=[]
var evidence={}
var gestures=0
var out=""
var capture_role=""
var metadata_only=false
var capture_info={}
var captured=[]
var routed=[]
const LANDMARKS=[10170,10514]
const OBJECTIVES=[
 "回到所選 · 護送拓荒隊 · 守住前哨\n村民 3/3 · 敵軍 0/6",
 "回到所選 · 護送拓荒隊 · 反攻已擊退\n重建倉庫 0/1 · 箭塔 1/1"
]
var began=0
var parked_menu
var park_launch=false
const History=preload("res://scripts/battle_history.gd")
func check(n,b):
 checks.append({"name":n,"passed":bool(b)})
 if not b:push_error(n)
 return bool(b)
func ck(n,b):return check(n,b)
func _initialize():
 began=Time.get_ticks_msec()
 print("VC_CAPTURE_BOOT escort_recovery")
 call_deferred("run")
func frames():
 for j in 4:await process_frame
func rect(node):
 var r=node.get_global_rect()
 return [r.position.x,r.position.y,r.size.x,r.size.y]
func at_point(p,index,down):
 var ev=InputEventScreenTouch.new()
 ev.index=index;ev.position=p;ev.pressed=down
 root.push_input(ev)
func trace_gesture(kind,waypoints):
 routed.append({"type":kind,"at_tick":g.tick_count if is_instance_valid(g) else null,"points":waypoints.map(func(p):return [p.x,p.y])})
 gestures+=1
func tap_point(p):
 trace_gesture("tap",[p])
 for down in [true,false]:
  at_point(p,61,down)
  park_match_at_launch()
  await process_frame
  park_match_at_launch()
func swipe(from,to):
 trace_gesture("swipe",[from,to])
 at_point(from,61,true);await process_frame
 for i in range(1,7):
  var dr=InputEventScreenDrag.new()
  dr.index=61;dr.position=from.lerp(to,i/6.0);dr.relative=(to-from)/6.0
  root.push_input(dr);await process_frame
 at_point(to,61,false);await frames()
func reached(button):
 return is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled and root.get_visible_rect().encloses(button.get_global_rect()) and button.size.x>=44 and button.size.y>=44
func tap(button):
 if not is_instance_valid(button) or not button.is_visible_in_tree():return false
 if not reached(button):return false
 await tap_point(button.get_global_rect().get_center())
 return true
func park_match_at_launch():
 if park_launch and is_instance_valid(parked_menu) and is_instance_valid(parked_menu.match_node):parked_menu.match_node.set_process(false)
func menu_tap(menu,name):
 var b=menu.buttons.get_node_or_null(name)
 if not is_instance_valid(b):return false
 if not menu.scroll.is_ancestor_of(b):
  park_launch=name=="LaunchMatchButton"
  var tapped=await tap(b)
  park_launch=false
  return tapped
 for attempt in 8:
  var r=menu.scroll.get_global_rect()
  if r.encloses(b.get_global_rect()) and reached(b):
   park_launch=name=="LaunchMatchButton"
   var tapped=await tap(b)
   park_launch=false
   return tapped
  var pos=r.get_center()
  var amount=minf(r.size.y*0.65,140)
  if b.get_global_rect().position.y<r.position.y:amount*=-1
  await swipe(pos+Vector2(0,amount*.5),pos-Vector2(0,amount*.5))
 return false

const Mission=preload("res://scripts/frontier_escort.gd")
const HOME=Vector3(-25,0,24)
var g
var orders=0
var builder=-1
var last_build=-1000
var strategy="recovery"
var counter=[]
var death={}

func submit(kind,data):
 g._submit(kind,data);orders+=1
func owned(records,kind):
 return records.filter(func(r):return r.get("owned",false) and r.get("alive",false) and r.get("kind","")==kind)
func affordable(kind,bank):
 for key in Rules.COSTS[kind]:
  if bank.get(key,0)<Rules.COSTS[kind][key]*1000:return false
 return true
func plot(kind,worker):
 for radius in [4,6,8,10]:
  for offset in [Vector3(1,0,0),Vector3(0,0,-1),Vector3(-1,0,0),Vector3(0,0,1),Vector3(1,0,1),Vector3(1,0,-1)]:
   var p=g._snap_build_position(kind,HOME+offset*radius)
   if g._placement_reason(kind,p,0,worker.id).is_empty():return p
 return Vector3.INF
func opening_decide():
 var records=g.faction_views[0].records().values()
 var workers=owned(records,"villager")
 var home=owned(records,"town_center")
 if home.is_empty():return
 var bank=g.economy.bank_milli(0)
 var army=records.filter(func(r):return r.get("owned",false) and r.get("alive",false) and r.get("kind","") in ["spearman","archer","cavalry","siege"])
 var population=0;var capacity=0
 for r in records:
  if not r.get("owned",false) or not r.get("alive",false):continue
  if r.category=="unit":population+=1
  if r.category=="building":
   population+=r.get("queue",[]).filter(func(q):return not q.get("research",false)).size()
   if r.built:capacity+=10 if r.kind=="town_center" else (5 if r.kind=="house" else 0)
 var barracks=owned(records,"barracks")
 var need=""
 if capacity-population<=2 and capacity<40:need="house"
 elif barracks.size()<2:need="barracks"
 # One ordinary build preview and command at a time; no site mutation.
 var unfinished=records.any(func(r):return r.get("owned",false) and r.category=="building" and not r.built)
 if need!="" and not unfinished and g.tick_count-last_build>=100 and affordable(need,bank):
  for w in workers:
   if w.state in ["build","repair"]:continue
   var p=plot(need,w)
   if not p.is_finite():continue
   submit("build",{"builder":w.id,"ids":[w.id],"kind":need,"position":p})
   builder=w.id;last_build=g.tick_count;return
 if workers.size()<10 and home[0].queue.is_empty() and capacity>population and affordable("villager",bank):
  submit("train",{"building":home[0].id,"kind":"villager"});return
 for b in barracks:
  if b.built and b.queue.is_empty() and capacity>population and army.size()<24 and affordable("spearman",bank):
   submit("train",{"building":b.id,"kind":"spearman"});return
 for i in workers.size():
  var w=workers[i]
  if w.state not in ["idle"]:continue
  var food=i%3!=0
  var candidates=records.filter(func(r):return r.get("alive",false) and not r.get("remembered",true) and r.get("category","")=="resource" and (r.kind=="berry" if food else r.kind in ["pine","oak"]))
  candidates.sort_custom(func(a,b):return w.pos.distance_squared_to(a.pos)<w.pos.distance_squared_to(b.pos))
  if not candidates.is_empty():submit("order",{"ids":[w.id],"target":candidates[0].id,"position":candidates[0].pos})


func note(k,v):
 evidence[k]=v
 print("ESCORT_NOTE ",k," ",JSON.stringify(v))
func sync():
 g._process(0);g._update_hud();g._layout_ui()
 await frames()
func all_owned_actors(kinds):
 return g.faction_views[0].records().values().filter(func(r):return r.get("team",-2)==0 and r.get("alive",false) and r.get("owned",false) and r.kind in kinds)
func army():return all_owned_actors(["spearman","archer","cavalry","siege"])
func citizen_party():return all_owned_actors(["villager"]).filter(func(n):return n.id in g.frontier_escort.villagers)
func safe():
 return is_instance_valid(g) and not g.paused and not g.game_over and Time.get_ticks_msec()-began<425000
func advance(ticks,condition):
 var duration=0
 while duration<ticks and safe() and not condition.call():
  g._process(Rules.TICK);duration+=1
 return duration
func checkpoint(stage,details={}):
 var line=JSON.stringify({"stage":stage,"ms":Time.get_ticks_msec()-began,"details":details})
 print("VC_CAPTURE_PROGRESS "+line)
 if out.is_empty() or not DirAccess.dir_exists_absolute(out):return
 var path=out+"/progress.jsonl"
 var f=FileAccess.open(path,FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
 if f!=null:f.seek_end();f.store_line(line);f.flush();f.close()
func real_frame(name,fields):
 var state=fields.duplicate(true);state.name=name
 checkpoint("state_ready",{"state":name,"tick":fields.get("tick",-1)})
 if not metadata_only:
  var draws=[0]
  var observer=func():draws[0]+=1
  RenderingServer.frame_post_draw.connect(observer)
  var start=Time.get_ticks_msec()
  checkpoint("draw_begin",{"state":name,"needed":2,"deadline_ms":45000})
  RenderingServer.render_loop_enabled=true
  while draws[0]<2 and Time.get_ticks_msec()-start<45000:await process_frame
  RenderingServer.render_loop_enabled=false
  RenderingServer.frame_post_draw.disconnect(observer)
  checkpoint("draw_end",{"state":name,"draws":draws[0],"ms":Time.get_ticks_msec()-start})
  if not check(name+" two actual renderer frame completions",draws[0]>=2):return false
  checkpoint("readback_begin",{"state":name})
  var img=root.get_texture().get_image()
  checkpoint("readback_end",{"state":name,"valid":img!=null})
  if not check(name+" actual native image dimensions",img!=null and not img.is_empty() and img.get_size()==Vector2i(568,320)):return false
  var palette={}
  for y in range(0,320,13):
   for x in range(0,568,13):palette[img.get_pixel(x,y).to_rgba32()]=true
  if not check(name+" real native unmodified view is nonblank",palette.size()>24):return false
  state.palette_samples=palette.size()
  state.file=name+".png"
  var path=out+"/"+state.file
  if not check(name+" native PNG saved",img.save_png(path)==OK):return false
  state.sha256=FileAccess.get_sha256(path)
  checkpoint("png_saved",{"state":name,"sha256":state.sha256})
 captured.append(state)
 return true




func entity_state(e):
 return {"id":e.id,"kind":e.kind,"team":e.team,"category":e.category,"alive":e.alive,
         "built":e.built,"pos":[e.pos.x,e.pos.y,e.pos.z],"hp":e.hp,"state":e.get("state",""),
         "mode":e.get("mode",""),"target":e.get("target",-1),"receipt":e.get("cost_receipt_id","")}
func capture_stage(index):
 var state=g.frontier_escort;var name=["counter-cleared","paid-rebuild-unfinished"][index]
 var b=g.objective_button;var msg=b.text
 var receipt_sites=g.entities.filter(func(e):return e.team==0 and e.alive and e.kind=="storehouse" and Mission.in_zone(e.pos))
 var queued=[]
 for item in g.commands:queued.append({"id":item.command_id,"sequence":item.sequence,"kind":item.type})
 var objective_visible=b.is_visible_in_tree() and root.get_visible_rect().encloses(b.get_global_rect()) and b.size.y>=44
 var terminal_visible=g.end_panel.is_visible_in_tree()
 var menu_open=g.compact_menu.is_visible_in_tree()
 var toast=g.toast_label.text if g.toast_label.is_visible_in_tree() else ""
 var tower=g._get_entity(100)
 if not check(name+" exact settled authoritative recovery state",
   g.tick_count==LANDMARKS[index] and state.stage==2 and state.launched and state.remaining==0 and state.living==3 and
   state.buildings=={"tower":100} and not tower.is_empty() and tower.alive and tower.built and g.match_report.building_losses=={"storehouse":1}
   and not g.game_over and not g.paused and not terminal_visible and not menu_open and objective_visible and not g.is_processing()):return false
 var expected=OBJECTIVES[1 if capture_role=="candidate" else 0]
 if not check(name+" text is exact from ordinary game objective button",msg==expected):return false
 var ft=b.get_theme_font("font");var fs=b.get_theme_font_size("font_size")
 var full_label=true
 var nm=b.get_theme_stylebox("normal")
 for line in msg.split("\n"):
  if ft.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x>maxf(0,b.size.x-nm.get_minimum_size().x):full_label=false
  for ch in line:
   if not ft.has_char(ch.unicode_at(0)):full_label=false
 if not check(name+" whole font and both lines fit the existing HUD button",full_label and (2*ft.get_height(fs))<=b.size.y):return false
 var paid={}
 var position_px=[]
 if index==0:
  if not check(name+" actual destroyed warehouse absent, toast gone and no replacement yet",receipt_sites.is_empty() and toast.is_empty()):return false
 else:
  if not check(name+" only one new paid incomplete site",receipt_sites.size()==1):return false
  var site=receipt_sites[0]
  var receipt=g.economy.receipt_view(site.get("cost_receipt_id",""))
  var bill=evidence["recovery_storehouse_bill"]
  if not check(name+" real open receipt for 80 wood, not yet a counted warehouse",
     site.id==107 and not site.built and site.pos==Vector3(-5,0,6) and not receipt.is_empty() and receipt.state=="open"
     and receipt.team==0 and receipt.cost_units=={"wood":80} and
     bill.raw_before.wood==515480 and bill.after.wood==435480 and
     bill.queued[0].enqueue_tick==10513 and bill.queued[0].command_id=="48" and queued.is_empty()):return false
  paid={"site":entity_state(site),"ledger_receipt":receipt}
  var screen=g.camera.unproject_position(site.pos+Vector3(0,.3,0));position_px=[screen.x,screen.y]
  if not check(name+" receipt site is actually within the viewport and unobstructed by top/objective/bottom HUD",
    root.get_visible_rect().has_point(screen) and not b.get_global_rect().has_point(screen) and
    not g.hud_top.get_global_rect().has_point(screen) and not g.hud_bottom.get_global_rect().has_point(screen)):return false
 var world_entities=g.entities.filter(func(e):return e.category in ["building","unit"]).map(entity_state)
 var xform=g.camera.global_transform
 var camera_vectors=[xform.basis.x,xform.basis.y,xform.basis.z,xform.origin,g.camera_focus]
 var data={"tick":g.tick_count,"stage":state.stage,"remaining":state.remaining,"living":state.living,
  "launched":state.launched,"counted":state.buildings.duplicate(true),"counter_ids":state.counter_ids.duplicate(),
  "objective":msg,"objective_rect":rect(b),"objective_visible":objective_visible,"menu_open":menu_open,"terminal_visible":terminal_visible,
  "toast":toast,"world_entities":world_entities,"camera_focus":str(g.camera_focus),"camera":camera_vectors.map(func(v):return [v.x,v.y,v.z]),
  "zoom":g.camera_zoom,"selected":g.selected.duplicate(),"command_sequence":g.command_sequence,"queued":queued,
  "bank":g.economy.bank_milli(0),"losses":g.match_report.building_losses.duplicate(true),
  "paid_unfinished":paid,"site_screen":position_px,"clock":g.time_label.text}
 var ok=await real_frame(name,data)
 return ok and check(name+" capture drew but did not advance simulation",g.tick_count==LANDMARKS[index] and not g.is_processing())

func finish(menu):
 check("exactly two capture states in original journey",captured.size()==2)
 check("exactly 32 actual routed touchscreen gestures",gestures==32 and routed.size()==32)
 var failed=checks.filter(func(x):return not x.passed).size()
 var data=capture_info
 data.checks=checks;data.failed=failed;data.gestures=gestures;data.routed=routed
 data.strategic_orders=orders;data.elapsed_ms=Time.get_ticks_msec()-began;data.evidence=evidence
 data.frames=captured;data.png_count=captured.filter(func(x):return x.has("sha256")).size()
 data.result="FAIL" if failed else ("METADATA_ONLY" if metadata_only else "RENDERED")
 if is_instance_valid(g) and g.is_inside_tree():
  data.tick=g.tick_count;data.stage=g.frontier_escort.stage;data.stage_ticks=g.frontier_escort.stage_ticks;data.finished=g.game_over;data.outcome=g.outcome;data.reason=g.end_reason;data.hp=g._first(0,"town_center").get("hp",0);data.alive=g.frontier_escort.living;data.losses=g.match_report.building_losses;data.built=g.match_report.completed;data.trained=g.match_report.trained;data.bank=g.economy.bank_milli(0);data.paused=g.paused;data.audit=g.economy.audit().ok
 var f=FileAccess.open(out+"/report.json",FileAccess.WRITE)
 if f==null:quit(2);return
 f.store_string(JSON.stringify(data,"  "));f.close()
 checkpoint("finish",{"checks":checks.size(),"failed":failed,"gestures":gestures,"tick":data.get("tick",-1),"stage":data.get("stage",-1),"outcome":data.get("outcome",""),"elapsed_ms":data.elapsed_ms,"png_count":data.png_count})
 if is_instance_valid(menu):menu.free()
 quit(0 if failed==0 else 1)

func button_reached(button,lane):
 return reached(button) and lane.get_global_rect().encloses(button.get_global_rect())
func seek(button,lane,horizontal):
 if not is_instance_valid(button):return -1
 for i in 16:
  if button_reached(button,lane):return i
  var band=lane.get_global_rect()
  var b=button.get_global_rect()
  var pos=band.get_center()
  var direct=Vector2.ZERO
  if horizontal:
   var d=1.0 if b.position.x>band.position.x else -1.0
   direct=Vector2(d*minf(155,band.size.x*.73),0)
  else:
   var d=1.0 if b.position.y>band.position.y else -1.0
   direct=Vector2(0,d*minf(125,band.size.y*.76))
  await swipe(pos+direct*.5,pos-direct*.5)
  await sync()
 return -1

func select_party():
 var before=g.command_sequence;var bank=g.economy.bank_milli(0)
 if not await tap(g.compact_menu_button):return false
 await sync()
 var button=g.compact_menu.find_child("EscortPartyButton",true,false)
 if not is_instance_valid(button):return false
 var initial={"button":rect(button),"scroll":rect(g.shortcut_scroll),"fully_reachable":button_reached(button,g.shortcut_scroll)}
 var n=await seek(button,g.shortcut_scroll,false)
 if not check("real selection route to the three designated villagers",n>=0 and await tap(button)):return false
 await sync()
 var exact=citizen_party().map(func(x):return x.id)
 exact.sort()
 var selected=g.selected.duplicate();selected.sort()
 note("party_shortcut",{"initial":initial,"menu_swipes":n,"selected":selected,"desired":exact,"no_command":g.command_sequence==before,"closed":not g.compact_menu.visible})
 return selected==exact and g.command_sequence==before and g.economy.bank_milli(0)==bank and not g.compact_menu.visible

func projected_world(world):
 return g.camera.unproject_position(world)
func ground_in_zone():
 for p in [Mission.TARGET,Vector3(-6,0,5),Vector3(-8,0,6),Vector3(-8,0,7),Vector3(-6,0,7),Vector3(-9,0,8),Vector3(-5,0,8),Vector3(-7,0,8)]:
  var at=projected_world(p)
  var cell=g._cell(g._world_at(at))
  if not g._box_point_in_world(at) or not g.work_memory[0].grid.region.has_point(cell) or g.work_memory[0].grid.is_point_solid(cell) or g._pick(at,true)>=0:continue
  return at
 return Vector2.INF

func target_worker(worker):
 var base=g.camera.unproject_position(worker.pos+Vector3(0,.6,0))
 for r in [0,4,8,12,16,24,31]:
  for i in 10:
   var p=base+r*Vector2.RIGHT.rotated(i*TAU/10)
   if g._box_point_in_world(p) and g._friendly_unit_pick(p,g._pick(p,true))==worker.id:return p
 return Vector2.INF

func lane_action(kind):
 for b in g.actions.get_children():
  if b is Button and b.has_meta("command_icon_kind") and b.get_meta("command_icon_kind")==kind:return b
 return null

func pan_up():
 # Native constant-span pair inside the lane not covered by the actual HUD.
 # An ordinary fallback to reveal more of the outpost after narrow layouts.
 for y in range(164,186,4):
  var a=Vector2(144,y);var b=Vector2(220,y);var delta=Vector2(0,27)
  if not [a,b,a+delta,b+delta].all(g._box_point_in_world):continue
  if not await drag_pair(a,b,delta):continue
  return true
 return false

func drag_pair(a,b,delta):
 var before=g.camera_focus
 trace_gesture("two_finger_pan",[a,b,a+delta,b+delta])
 at_point(a,2,true);at_point(b,3,true);await process_frame
 for i in range(1,7):
  for j in 2:
   var ev=InputEventScreenDrag.new();ev.index=2+j;ev.position=([a,b][j])+delta*(i/6.0);ev.relative=delta/6.0;root.push_input(ev)
  await process_frame
 at_point(a+delta,2,false);at_point(b+delta,3,false);await sync()
 return g.camera_focus!=before and g.all_touch_ids.is_empty()

func build_plan(kind,worker):
 var checked={}
 var results=[]
 for z in range(3,10):
  for x in range(-11,-2):
   var plot=g._snap_build_position(kind,Vector3(x,0,z))
   if checked.has(plot):continue
   checked[plot]=true
   if not Mission.in_zone(plot) or not g._placement_reason(kind,plot,0,worker.id).is_empty():continue
   var v=g.camera.unproject_position(plot)
   var pointer=g._point(g._cell(g._world_at(v)))
   var real_point=g._snap_build_position(kind,pointer)
   var candidate=g._box_point_in_world(v) and real_point==plot
   results.append({"position":plot,"screen":v,"world_touch":candidate,"screen_in_view":root.get_visible_rect().has_point(v),"center_distance":plot.distance_to(Mission.TARGET)})
 results.sort_custom(func(a,b):return a.center_distance<b.center_distance)
 return results

func apply_outpost_site(kind,step):
 await sync()
 var candidate={}
 for w in all_owned_actors(["villager"]):
  if w.state in ["build","repair"] or not Mission.in_zone(w.pos):continue
  var p=target_worker(w)
  if p.is_finite():candidate={"worker":w,"point":p};break
 if candidate.is_empty():
  for w in all_owned_actors(["villager"]):
   var p=target_worker(w)
   if p.is_finite():candidate={"worker":w,"point":p};break
 if not check(step+" ordinary visible worker can actually be touched",not candidate.is_empty()):return false
 var w=candidate.worker
 var seq=g.command_sequence;var started=g.economy.bank_milli(0)
 await tap_point(candidate.point);await sync()
 if not check(step+" native world selection leaves only selected builder",g.selected==[w.id] and g.command_sequence==seq):return false
 var act=lane_action(kind)
 var initial=rect(act) if is_instance_valid(act) else []
 var n=await seek(act,g.action_scroll,true)
 if not check(step+" normal build button reached through real swipes",n>=0 and await tap(act)):return false
 await sync()
 if not check(step+" real place mode no payment",g.build_mode==kind and g.command_sequence==seq and g.economy.bank_milli(0)==started):return false
 var poses=build_plan(kind,w)
 var touchable=poses.filter(func(p):return p.world_touch)
 var best=touchable[0] if not touchable.is_empty() else {}
 var note_before={"legal_in_zone":poses.size(),"legal_in_view":poses.filter(func(p):return p.screen_in_view).size(),"legal_touchable":touchable.size(),"closest":poses[0] if not poses.is_empty() else {},"center_screen":str(g.camera.unproject_position(Mission.TARGET)),"center_world_reachable":g._box_point_in_world(g.camera.unproject_position(Mission.TARGET)),"top":rect(g.hud_top),"banner":rect(g.tutorial_panel) if g.tutorial_panel.visible else [],"bottom":rect(g.hud_bottom),"camera":str(g.camera_focus),"strip_swipes":n,"button_initial":initial}
 if best.is_empty():
  var pans=0
  while best.is_empty() and pans<4:
   if not await pan_up():break
   pans+=1
   touchable=build_plan(kind,w).filter(func(p):return p.world_touch)
   best=touchable[0] if not touchable.is_empty() else {}
  note_before.pans=pans
  note_before.camera_after=str(g.camera_focus)
 note(step+"_layout",note_before)
 if not check(step+" normal in-zone preview position can be reached",not best.is_empty()):return false
 await tap_point(best.screen);await sync()
 if not check(step+" actual preview says in-zone and still unpaid",g.build_preview_held and g._escort_build_zone_hint()=="前哨內，完成先計" and affordable(kind,started) and g.economy.bank_milli(0)==started and button_reached(g.build_confirm,g.action_scroll)):return false
 await tap(g.build_confirm)
 var queued=g.commands.duplicate(true)
 if not check(step+" actual confirm produces exactly one correct snapped world position",queued.size()==1 and queued[0].type=="build" and queued[0].kind==kind and g._snap_build_position(kind,queued[0].position)==best.position and g.command_sequence==seq+1):return false
 var previous=g.economy.stats_view(0).delivered.duplicate()
 g._process(Rules.TICK)
 var post=g.economy.bank_milli(0);var delivered=g.economy.stats_view(0).delivered
 for res in started:
  if post[res]!=started[res]-1000*Rules.COSTS[kind].get(res,0)+delivered.get(res,0)-previous.get(res,0):
   return check(step+" only exact original requested cost paid",false)
 note(step+"_bill",{"queued":queued,"expected_snapped":best.position,"raw_before":started,"after":post,"count":g.commands.size()})
 if step.begins_with("recovery_"):
  await sync()
  note("paid_recovery_still_incomplete",{"t":g.tick_count,"copy":g.objective_button.text,"bank":post,"stage":g.frontier_escort.stage,"ends":g.game_over})
  if not await capture_stage(1):return false
 var time=await advance(2700,func():return g.frontier_escort.buildings.has(kind))
 await sync()
 var built=g.frontier_escort.buildings.has(kind)
 note(step+"_birth",{"used_swipes":n,"actual_position":best.position,"screen":best.screen,"ticks":time,"t":g.tick_count,"active":built,"stage":g.frontier_escort.stage,"bank":g.economy.bank_milli(0),"unit":w.id})
 return check(step+" normal completed paid outpost building counted",built)

func tactical_decision():
 var hostile=g.faction_views[0].records().values().filter(func(r):return r.get("alive",false) and not r.get("remembered",true) and r.get("team",-1)==1 and r.category=="unit")
 var own=army()
 if hostile.is_empty():
  var frontline=Vector3(-7,0,0)
  var moving=own.filter(func(r):return r.state=="idle" and r.pos.distance_to(frontline)>5)
  if not moving.is_empty():submit("advance",{"ids":moving.map(func(r):return r.id),"position":frontline})
 else:
  hostile.sort_custom(func(a,b):return a.pos.distance_to(Mission.TARGET)<b.pos.distance_to(Mission.TARGET))
  var target=hostile[0]
  var men=own.filter(func(r):return r.state!="attack" or r.target!=target.id)
  if not men.is_empty():submit("order",{"ids":men.map(func(r):return r.id),"target":target.id,"position":target.pos})

func inspect_recovery():
 await sync()
 var b=g.objective_button
 var freeze=g.command_sequence
 if not await capture_stage(0):return false
 var detail={"tick":g.tick_count,"stage":g.frontier_escort.stage,"objective":b.text,"objective_visible":b.is_visible_in_tree(),"objective_rect":rect(b),"remaining":g.frontier_escort.remaining,"buildings":g.frontier_escort.buildings.duplicate(),"own_losses":g.match_report.building_losses.duplicate(),"toast":g.toast_label.text if g.toast_label.is_visible_in_tree() else "","clat":g.frontier_escort.living}
 if await tap(g.compact_menu_button):
  await sync()
  detail.menu=g.mission_label.text
  detail.menu_rect=rect(g.mission_label)
  for x in g.compact_menu.find_children("*","Button",true,false):
   if x.text=="關閉" and reached(x):await tap(x);break
  await sync()
 detail.no_new_order=g.command_sequence==freeze
 note("zero_enemies_recovery_gate",detail)
 if not check("real drawer opened and closed without moving or commanding",detail.no_new_order and detail.has("menu") and not g.compact_menu.is_visible_in_tree()):return false
 var candidate=capture_role=="candidate"
 var expected_tail="在前哨界線內付費重建倉庫，完成才計。" if candidate else "擊退餘下0名敵軍；前哨被毀可重建。"
 return check("actual settled drawer is correct for the pinned source and reports one missing warehouse",detail.menu.contains("倉庫 0/1 · 箭塔 1/1") and detail.menu.ends_with(expected_tail))

func gather_replacement_material(kind):
  var required=Rules.COSTS[kind]
  for resource in required:
   if g.economy.bank_milli(0).get(resource,0)>=required[resource]*1000:continue
   var records=g.faction_views[0].records().values()
   var candidates=records.filter(func(r):return r.get("alive",false) and not r.get("remembered",true) and (r.kind=="stone" if resource=="stone" else r.kind in ["pine","oak"]))
   var available=all_owned_actors(["villager"]).filter(func(w):return not (w.id in g.frontier_escort.villagers) and w.state not in ["repair","build"])
   if candidates.is_empty() or available.is_empty():return false
   for j in mini(4,available.size()):
    var w=available[j]
    candidates.sort_custom(func(a,b):return w.pos.distance_squared_to(a.pos)<w.pos.distance_squared_to(b.pos))
    var site=candidates[mini(j,candidates.size()-1)]
    submit("order",{"ids":[w.id],"target":site.id,"position":site.pos})
  var start=g.tick_count
  await advance(4200,func():return affordable(kind,g.economy.bank_milli(0)))
  note("earned_replacement_"+kind,{"t":g.tick_count,"wait_ticks":g.tick_count-start,"bank":g.economy.bank_milli(0),"ordinary_delivery":g.economy.stats_view(0).delivered})
  return affordable(kind,g.economy.bank_milli(0))
func recovery_dispatch():
 var to=Mission.TARGET
 var ids=citizen_party().map(func(e):return e.id)
 if ids.is_empty():return false
 submit("order",{"ids":ids,"position":to})
 await advance(1300,func():return citizen_party().any(func(r):return Mission.in_zone(r.pos)))
 await sync()
 return citizen_party().any(func(r):return Mission.in_zone(r.pos))

func run():
 RenderingServer.render_loop_enabled=false
 var args=OS.get_cmdline_user_args()
 if args.size() not in [6,7] or args[1] not in ["baseline","candidate"] or (args.size()==7 and args[6]!="--metadata-only"):quit(2);return
 out=args[0];capture_role=args[1];metadata_only=args.size()==7
 if not out.begins_with("/") or DirAccess.dir_exists_absolute(out) or FileAccess.file_exists(out) or DirAccess.make_dir_recursive_absolute(out)!=OK:quit(2);return
 root.size=Vector2i(568,320);await frames()
 var engine=Engine.get_version_info()
 capture_info={"scope":"Actual native 568x320 Chapter 3 after exact isolated earned Chapter 2 test record. Includes 32 real routed synthetic taps/swipes/pan for campaign, field and paid construction. Economy/retreat/combat use visible-target in-engine stock commands, not direct state setup. No injected actors, funds, positions, camera, outcome or compositing.","build":Rules.BUILD_ID,"role":capture_role,"size":[568,320],"engine":engine,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"video_adapter":RenderingServer.get_video_adapter_name(),"game_sha":FileAccess.get_sha256("res://scripts/game.gd"),"rules_sha":FileAccess.get_sha256("res://scripts/rules.gd"),"director_sha":FileAccess.get_sha256("res://scripts/frontier_escort.gd"),"metadata_only":metadata_only}
 checkpoint("initialize",{"build":capture_info.build,"role":capture_role,"display":capture_info.display,"adapter":capture_info.video_adapter})
 if not check("official 4.6.3 exact 568x320 and all three exact runtime sources",engine.hash=="7d41c59c457bd5a245092b4e7eb2d833e3b3f8c3" and engine.hex==0x040603
  and capture_info.build==args[2] and capture_info.game_sha==args[3] and capture_info.rules_sha==args[4] and capture_info.director_sha==args[5]
  and root.size==Vector2i(568,320) and (metadata_only or (capture_info.display=="X11" and capture_info.renderer=="gl_compatibility" and "llvmpipe" in capture_info.video_adapter.to_lower()))):finish(null);return
 var menu=load("res://main_menu.tscn").instantiate();parked_menu=menu
 var pg=preload("res://scripts/campaign_progress.gd")
 menu.campaign_progress_path="user://isolated-escort-progress.json"
 menu.history_path="user://isolated-escort-history.json"
 var earned=pg.read(menu.campaign_progress_path)
 if not check("isolated progress exact 39 earned bytes from prior Chapter 2 victory",earned.ok and earned.completed==2 and earned.revision==2
  and FileAccess.get_sha256(menu.campaign_progress_path)=="1ed0cf3f8ef3779be8d16b055e99714ba576df8b39aa3dcdd08e0e6065c4600e"):finish(menu);return
 root.add_child(menu);await frames()
 for n in ["StartMatchButton","CampaignMenuButton","CampaignChapterButton"]:
  if not check("actual normal campaign menu "+n,await menu_tap(menu,n)):finish(menu);return
  await frames()
 if not check("actual unlocked Chapter 3 briefing",menu.page=="setup" and menu.selected_campaign==2 and menu.description.text.contains("護送")):finish(menu);return
 note("briefing",menu.description.text)
 if not check("normal Launch touch",await menu_tap(menu,"LaunchMatchButton")):finish(menu);return
 if not is_instance_valid(menu.match_node):await process_frame
 g=menu.match_node
 if not check("real isolated authored Escort ordinary tick zero",is_instance_valid(g) and g.campaign_chapter==2 and g.skirmish_mode=="escort" and g.tick_count==0 and not g.test_mode):finish(menu);return
 g.set_process(false);g.history_path=menu.history_path;await sync()
 var start=g.economy.bank_milli(0)
 var roster=0
 var saving=false
 while safe() and g.tick_count<15000:
  roster=army().size()
  var bank=g.economy.bank_milli(0)
  if roster>=12 and bank.wood>=160000 and bank.stone>=100000:break
  if roster>=12 and not saving:
   saving=true
   var workers=all_owned_actors(["villager"]).filter(func(w):return not (w.id in g.frontier_escort.villagers) and w.state not in ["build","repair"])
   var trees=g.faction_views[0].records().values().filter(func(r):return r.get("alive",false) and not r.get("remembered",true) and r.kind in ["pine","oak"])
   for i in mini(workers.size(),4):
    if trees.is_empty():break
    var w=workers[i]
    trees.sort_custom(func(a,b):return w.pos.distance_squared_to(a.pos)<w.pos.distance_squared_to(b.pos))
    var tree=trees[mini(i,trees.size()-1)]
    submit("order",{"ids":[w.id],"target":tree.id,"position":tree.pos})
   note("ordinary_reserved_wood",{"tick":g.tick_count,"army":roster,"bank":bank})
  if not saving and g.tick_count%100==0:opening_decide()
  g._process(Rules.TICK)
  if g.tick_count%1000==0:print("ESCORT_ECON_PROGRESS ",g.tick_count," army=",roster," bank=",JSON.stringify(bank))
 if not check("normal stock economic preparation trains and reserves the first pair",army().size()>=12 and g.economy.bank_milli(0).wood>=160000 and g.economy.audit().ok):finish(menu);return
 await sync()
 note("economic_opening",{"t":g.tick_count,"roster":army().size(),"bank":g.economy.bank_milli(0),"opening":start,"paid":g.match_report.trained})
 if not check("actual party shortcut selects whole authored party without issuing moves",await select_party()):finish(menu);return
 var focus=g.camera_focus;var bank=g.economy.bank_milli(0);var seq=g.command_sequence
 if not check("actual objective button fits full 44 and genuinely focuses public target",await tap(g.objective_button)):finish(menu);return
 await sync()
 if not check("locating public outpost neither cheats vision nor places orders",g.camera_focus==Mission.TARGET and g.camera_focus!=focus and g.command_sequence==seq and g.economy.bank_milli(0)==bank):finish(menu);return
 var screen=ground_in_zone()
 if not check("natural objective-focused land tap can reach selected party destination",screen.is_finite()):finish(menu);return
 await tap_point(screen)
 if not check("actual ground touch sends one ordinary authored villager move",g.commands.size()==1 and g.commands[0].type=="order" and g.commands[0].ids==g.selected and g.commands[0].target==-1):finish(menu);return
 await advance(2400,func():return g.frontier_escort.stage>=1)
 await sync()
 if not check("at least one designated villager arrives by ordinary movement",g.frontier_escort.stage==1 and g.frontier_escort.living>0):finish(menu);return
 note("arrival",{"tick":g.tick_count,"used_world_screen":screen,"chosen_world":g._world_at(screen),"party":g.selected.duplicate(),"clock":g.time_label.text,"objective":g.objective_button.text})
 if not await apply_outpost_site("storehouse","first_storehouse"):finish(menu);return
 if not await apply_outpost_site("tower","first_tower"):finish(menu);return
 if not check("both actual buildings naturally start 30-second counter",g.frontier_escort.stage==2 and g.frontier_escort.due==g.frontier_escort.stage_ticks[1]+600):finish(menu);return
 note("counter_preparation",{"tick":g.tick_count,"due":g.frontier_escort.due,"copy":g.objective_button.text,"buildings":g.frontier_escort.buildings.duplicate(),"bank":g.economy.bank_milli(0)})
 if strategy=="recovery":submit("order",{"ids":citizen_party().map(func(r):return r.id),"position":HOME})
 var defend=strategy!="recovery"
 var settle_from=-1
 while safe() and g.tick_count<35000:
  var state=g.frontier_escort
  if state.launched and counter.is_empty():
   counter=state.counter_ids.duplicate();note("counter_launch",{"ids":counter,"t":g.tick_count})
  if state.launched and not defend and (state.buildings.size()<2 or g.tick_count>state.due+1700):
   defend=true
   death={"t":g.tick_count,"own_losses":g.match_report.building_losses.duplicate(),"still_built":state.buildings.duplicate(),"remaining":state.remaining}
   note("late_defense_order",death)
  if state.launched and defend and g.tick_count%100==0:tactical_decision()
  if state.launched and state.remaining==0 and not g.game_over and state.buildings.size()<2:
   settle_from=g.tick_count;break
  g._process(Rules.TICK)
  if g.tick_count%1000==0:print("ESCORT_DEF_PROGRESS ",g.tick_count," remain=",state.remaining," stages=",state.stage," own=",army().size())
 if settle_from>=0:
  await advance(160,func():return false)
  if not await inspect_recovery():finish(menu);return
  if not check("safety saved at least one designated villager and unguarded site loss was real",g.frontier_escort.living>0 and not g.match_report.building_losses.is_empty()):finish(menu);return
  if not check("ordinary return route can recover an alive builder",await recovery_dispatch()):finish(menu);return
  # Repair/replace via ordinary paid route. No free grant: budget checks are reported.
  for k in ["storehouse","tower"]:
   if g.frontier_escort.buildings.has(k):continue
   if not check("real gathered bank covers replacement "+k,await gather_replacement_material(k)):finish(menu);return
   if not await apply_outpost_site(k,"recovery_"+k):finish(menu);return
 await sync()
 if not check("real authored victory completed all three stages",g.game_over and g.end_reason=="escort_complete" and g.outcome=="victory" and g.frontier_escort.stage==3 and g.frontier_escort.living>0 and g.economy.audit().ok):finish(menu);return
 var p=pg.read(menu.campaign_progress_path)
 var h=History.read_history(menu.history_path)
 note("terminal",{"stage_ticks":g.frontier_escort.stage_ticks,"party_alive":g.frontier_escort.living,"buildings":g.frontier_escort.buildings.duplicate(),"progress":p.completed,"revision":p.revision,"history_ok":h.ok,"outcome":g.outcome,"tick":g.tick_count,"text":g.end_title.text,"counter":counter,"end_action":g.end_setup_button.text,"action_rect":rect(g.end_setup_button)})
 if not check("true campaign completion action reachable and only returns to completion page",p.ok and p.completed==3 and p.revision==3 and h.ok and h.entries.size()==1 and await tap(g.end_setup_button)):finish(menu);return
 await frames()
 check("real completion page says three done without another match",menu.page=="campaign" and menu.description.text.contains("已完成 3 / 3") and menu.match_node==g)
 finish(menu)
