extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var checks=[]
var evidence={}
var gestures=0
var out=""
var began=0
var parked_menu
var requested_size=Vector2i.ZERO
var resize_after_arrival=false
var park_launch=false
const History=preload("res://scripts/battle_history.gd")
func check(n,b):
 checks.append({"name":n,"passed":bool(b)})
 if not b:push_error(n)
 return bool(b)
func ck(n,b):return check(n,b)
func _initialize():
 began=Time.get_ticks_msec()
 print("ESCORT_NATIVE_PROBE_BOOT")
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
func tap_point(p):
 gestures+=1
 for down in [true,false]:
  at_point(p,61,down)
  park_match_at_launch()
  await process_frame
  park_match_at_launch()
func swipe(from,to):
 gestures+=1
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
var peak_army=0
var counter=[]
var death={}
var model_progress={}

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
func finish(menu):
 var failed=checks.filter(func(x):return not x.passed).size()
 var data={"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"game_sha":FileAccess.get_sha256("res://scripts/game.gd"),"rules_sha":FileAccess.get_sha256("res://scripts/rules.gd"),"manifest_sha":FileAccess.get_sha256("res://reports/build-manifest.json"),"checks":checks,"failed":failed,"gestures":gestures,"strategic_orders":orders,"build":Rules.BUILD_ID,"size":[root.size.x,root.size.y],
           "elapsed_ms":Time.get_ticks_msec()-began,"strategy":strategy,"evidence":evidence,"scope":"Exact native routed campaign, mission selection, world move and paid building taps; ordinary in-engine stock strategy commands for economic preparation, retreat and combat. No scenario footage, player state, injections or Web."}
 if is_instance_valid(g) and g.is_inside_tree():
  data.tick=g.tick_count;data.stage=g.frontier_escort.stage;data.stage_ticks=g.frontier_escort.stage_ticks;data.finished=g.game_over;data.outcome=g.outcome;data.reason=g.end_reason;data.hp=g._first(0,"town_center").get("hp",0);data.alive=g.frontier_escort.living;data.losses=g.match_report.building_losses;data.built=g.match_report.completed;data.trained=g.match_report.trained;data.bank=g.economy.bank_milli(0);data.paused=g.paused;data.audit=g.economy.audit().ok
 var f=FileAccess.open(out,FileAccess.WRITE)
 if f==null:quit(2);return
 f.store_string(JSON.stringify(data,"  "));f.close()
 print("ESCORT_RESULT ",JSON.stringify({"checks":checks.size(),"failed":failed,"gestures":gestures,"tick":data.get("tick",-1),"stage":data.get("stage",-1),"outcome":data.get("outcome",""),"elapsed_ms":data.elapsed_ms}))
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
 gestures+=1
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
   var covered=[]
   for cover in [g.hud_top,g.hud_bottom,g.minimap,g.compact_menu_dismiss,g.end_panel,g.tutorial_panel,g.context_details]:
    if cover.is_visible_in_tree() and cover.get_global_rect().has_point(v):covered.append(str(cover.name))
   results.append({"position":plot,"screen":v,"world_touch":candidate,"screen_in_view":root.get_visible_rect().has_point(v),"center_distance":plot.distance_to(Mission.TARGET),"real_snap_matches":real_point==plot,"cover":covered})
 results.sort_custom(func(a,b):return a.center_distance<b.center_distance)
 return results

func save_real_view(label):
 var owned=g.faction_views[0].records().values().filter(func(r):return r.get("owned",false) and r.get("alive",false))
 owned.sort_custom(func(a,b):return a.id<b.id)
 var public_actors=owned.map(func(r):return [r.id,r.kind,str(r.pos),r.get("hp",-1),r.get("built",false)])
 note(label+"_frame_state",{"tick":g.tick_count,"camera":str(g.camera.global_transform),"camera_focus":str(g.camera_focus),"zoom":g.camera_zoom,"bank":g.economy.bank_milli(0),"sequence":g.command_sequence,"selected":g.selected.duplicate(),"pending":g.commands.size(),"mission_stage":g.frontier_escort.stage,"owned_public":public_actors})
 note(label+"_frame_presentation",{"held":g.build_preview_held,"placement_ok":g.placement_ok,"confirm_disabled":g.build_confirm.disabled,"tutorial_panel":g.tutorial_panel.visible,"inline_status":g.selection_summary.text})
 var dir=OS.get_environment("VC_NATIVE_PLACEMENT_CAPTURE_DIR")
 if dir.is_empty():return true
 if not check("native Compatibility llvmpipe capture target",DisplayServer.get_name()!="headless" and RenderingServer.get_current_rendering_method()=="gl_compatibility" and "llvmpipe" in RenderingServer.get_video_adapter_name().to_lower() and root.size==Vector2i(568,320) and DirAccess.dir_exists_absolute(dir)):return false
 var draws=[0]
 var marker=func():draws[0]+=1
 RenderingServer.frame_post_draw.connect(marker)
 RenderingServer.render_loop_enabled=true
 var start=Time.get_ticks_msec()
 while draws[0]<3 and Time.get_ticks_msec()-start<30000:await process_frame
 RenderingServer.render_loop_enabled=false
 RenderingServer.frame_post_draw.disconnect(marker)
 if not check(label+" three genuine renderer completions",draws[0]>=3):return false
 var image=root.get_texture().get_image()
 if not check(label+" untampered viewport dimensions",image!=null and not image.is_empty() and image.get_size()==Vector2i(568,320)):return false
 var distinct={}
 for x in range(0,568,17):
  for y in range(0,320,17):distinct[image.get_pixel(x,y).to_rgba32()]=true
 if not check(label+" not a blank framebuffer",distinct.size()>24):return false
 var path=dir+"/"+label+".png"
 if not check(label+" stores original Godot viewport PNG",not FileAccess.file_exists(path) and image.save_png(path)==OK):return false
 note(label+"_original_png",{"file":label+".png","sha256":FileAccess.get_sha256(path),"actual_tick":g.tick_count,"camera":str(g.camera.global_transform),"original_native":true,"held":g.build_preview_held,"viewport":root.size})
 return true

func apply_outpost_site(kind,step):
 if resize_after_arrival:root.size=Vector2i(568,320)
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
 if resize_after_arrival:
  root.size=requested_size
  await sync()
  if not check(step+" actual resize retains selection, not a held construction intent",g.build_mode.is_empty() and g.selected==[w.id] and g.command_sequence==seq and g.economy.bank_milli(0)==started):return false
  note(step+"_placement_only_resize",{"size":root.size,"command_sequence":g.command_sequence,"tick":g.tick_count})
 var act=lane_action(kind)
 var initial=rect(act) if is_instance_valid(act) else []
 var n=await seek(act,g.action_scroll,true)
 if not check(step+" normal build button reached through real swipes",n>=0 and await tap(act)):return false
 await sync()
 if not check(step+" real place mode no payment",g.build_mode==kind and g.command_sequence==seq and g.economy.bank_milli(0)==started):return false
 var poses=build_plan(kind,w)
 var touchable=poses.filter(func(p):return p.world_touch)
 var best=touchable[0] if not touchable.is_empty() else {}
 var truly_covered=poses.filter(func(p):return p.real_snap_matches and p.cover==[str(g.tutorial_panel.name)])
 if root.size.x>root.size.y and not truly_covered.is_empty():
  var chosen=truly_covered[0]
  var probe=chosen.screen
  var start_camera=g.camera.global_transform
  var start_point=g.pointer_world
  var prior_tick=g.tick_count
  var held=g.build_preview_held
  var legal=g._placement_reason(kind,chosen.position,0,w.id).is_empty()
  await tap_point(probe);await sync()
  var blocked=g.pointer_world==start_point and g.build_preview_held==held and g.command_sequence==seq and g.camera.global_transform==start_camera and g.economy.bank_milli(0)==started
  check(step+" actual legal near-center site tap ignored by current HUD without command",legal and blocked and g.tick_count==prior_tick)
  note(step+"_blocking_real_touch",{"screen":probe,"position":chosen.position,"legal_at_tap":legal,"t":g.tick_count,"banner":rect(g.tutorial_panel),"label":g.toast_label.text,"blocked":blocked,"held_after":g.build_preview_held,"no_orders":g.command_sequence==seq})
  if not await save_real_view(step+"-plot-tapped"):return false
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
 note_before.block_reason={}
 note_before.legal_candidate_projection=[]
 var tutorial_name=str(g.tutorial_panel.name)
 for p in poses:
  var key="touch_reachable" if p.world_touch else ("snap_mismatch" if not p.real_snap_matches else ("outside_view" if not p.screen_in_view else (("only_placement_banner" if p.cover==[tutorial_name] else "other_gui") if not p.cover.is_empty() else "unclassified")))
  note_before.block_reason[key]=note_before.block_reason.get(key,0)+1
  note_before.legal_candidate_projection.append(p)
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
 if args.size() not in [3,4]:quit(2);return
 requested_size=Vector2i(int(args[0]),int(args[1]))
 # Keep ordinary menu/party interaction at the reference supported size,
 # then exercise small viewport pressure without a separate menu blocker.
 resize_after_arrival=requested_size.x<568 and requested_size.x>requested_size.y
 root.size=Vector2i(568,320) if resize_after_arrival else requested_size
 out=args[2]
 if args.size()==4:strategy=args[3]
 var menu=load("res://main_menu.tscn").instantiate();parked_menu=menu
 var pg=preload("res://scripts/campaign_progress.gd")
 menu.campaign_progress_path="user://isolated-escort-progress.json"
 menu.history_path="user://isolated-escort-history.json"
 var earned=pg.read(menu.campaign_progress_path)
 if not check("isolated progress really comes from exact prior Chapter 2 victory",earned.ok and earned.completed==2 and earned.revision==2):finish(menu);return
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
 while safe() and g.tick_count<16000:
  roster=army().size()
  var bank=g.economy.bank_milli(0)
  if bank.wood>=160000 and bank.stone>=100000:break
  if g.tick_count%100==0:opening_decide()
  g._process(Rules.TICK)
  if g.tick_count%1000==0:print("ESCORT_ECON_PROGRESS ",g.tick_count," army=",roster," bank=",JSON.stringify(bank))
 if not check("deterministic untouched stock can afford both original objective buildings",g.economy.bank_milli(0).wood>=160000 and g.economy.audit().ok):finish(menu);return
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
 note("pilot_stop","Only opening routed party/placement flow; deliberate independent stop before the counter, not full mission.")
 finish(menu)
