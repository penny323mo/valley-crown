extends SceneTree
# Ordinary new mode candidate natural play. No stores, HP, entity, fog or clock edits.
const HOME_BERRY=Vector3(-26.5,0,25.5)
const FRONT=Vector3(-11,0,15)
const FOOD_GOAL=Vector3(-9,0,11.5)
const WOOD_GOAL=Vector3(-12,0,9)
const LO=Vector2i(-16,12)
const HI=Vector2i(-7,18)
var g
var checks=[]
var images={}
var output_dir=""
var show_images=false
var first_capture=false
var requested_name=""
func check(name,ok):
 checks.append({"name":name,"passed":bool(ok)})
 if not ok:push_error(name)
func settle():
 for i in 4:await process_frame
func tap(p:Vector2):
 for pressed in [true,false]:
  var event=InputEventScreenTouch.new();event.index=7;event.position=p;event.pressed=pressed
  root.push_input(event);await process_frame
 await settle()
func touch_by_name(control:String):
 await settle()
 var b=shell.buttons.get_node_or_null(control)
 if not is_instance_valid(b):
  check("visible real menu action "+control,false);return
 if not root.get_visible_rect().encloses(b.get_global_rect()):
  var parent=b.get_parent()
  while is_instance_valid(parent):
   if parent is ScrollContainer:parent.ensure_control_visible(b);await settle();break
   parent=parent.get_parent()
 check("visible real menu action "+control,b.is_visible_in_tree() and b.size.y>=44 and root.get_visible_rect().encloses(b.get_global_rect()))
 await tap(b.get_global_rect().get_center())
func frame(key:String):
 if not show_images:return
 RenderingServer.render_loop_enabled=true
 await RenderingServer.frame_post_draw
 var im=root.get_texture().get_image()
 RenderingServer.render_loop_enabled=false
 DirAccess.make_dir_recursive_absolute(output_dir)
 var path=output_dir+"/"+key+".png"
 var ok=im.save_png(path)==OK and im.get_width()==390 and im.get_height()==844
 check("actual rendered scene "+key,ok)
 images[key]={"width":im.get_width(),"height":im.get_height(),"sha256":FileAccess.get_sha256(path)}
var witnesses=[]
var team=[]
var house=-1
var builder=-1
var build_tick=-1
var last_order={}
var last_harvest=0
var exported=[]
var contacts=0
var hostile_ids=[]
var visible_hostile_damage={}
var assault_sent=false
var barracks_order=false
var train_tick=-1
var shell
var say_war=-1000
var depot_total={"food":0,"wood":0}
var home_total={"food":0,"wood":0}
func _initialize():call_deferred("run")
func known():return g.faction_views[0].records().values()
func ordinary(id,spot,filter_types:Array=[]):
 if filter_types.is_empty():
  g._submit("order",{"ids":[id],"position":spot})
  return true
 var r=known().filter(func(q):return q.category=="resource" and q.alive and not q.remembered and q.kind in filter_types and q.pos.distance_to(spot)<5)
 r.sort_custom(func(a,b):return a.pos.distance_squared_to(spot)<b.pos.distance_squared_to(spot))
 if r.is_empty():return false
 g._submit("order",{"ids":[id],"target":r[0].id,"position":r[0].pos})
 return true
func zone(p):return p.x>=LO.x and p.x<=HI.x and p.z>=LO.y and p.z<=HI.y
func choose_zone():
 var choices=[]
 for x in range(LO.x,HI.x+1):
  for z in range(LO.y,HI.y+1):
   var p=Vector3(x,0,z)
   if g._placement_reason("storehouse",p,0,builder).is_empty():choices.append(p)
 choices.sort_custom(func(a,b):return a.distance_squared_to(FRONT)<b.distance_squared_to(FRONT))
 return choices[0] if not choices.is_empty() else Vector3.INF
func note_phase():
 if g.tick_count%20!=0:return
 if g.tick_count>=0 and not barracks_order:
  for p in [Vector3(-29.5,0,28.5),Vector3(-26.5,0,29.5),Vector3(-22.5,0,26.5)]:
   if not g._placement_reason("barracks",p,0,team[4]).is_empty():continue
   g._submit("build",{"ids":[team[4]],"builder":team[4],"position":p,"kind":"barracks"})
   barracks_order=true;break
 if train_tick<0:
  for r in known():
   if r.owned and r.built and r.kind=="barracks" and r.queue.is_empty() and g.economy.bank_milli(0).food>=60000:
    g._submit("train",{"building":r.id,"kind":"spearman"});train_tick=g.tick_count;break
 var military=known().filter(func(a):return a.owned and a.alive and a.kind in ["spearman","archer"])
 if g.tick_count>200 and not assault_sent:
  assault_sent=true
  g._submit("advance",{"ids":military.map(func(q):return q.id),"position":Vector3(-7.5,0,11.5)})
 var enemies=known().filter(func(a):return a.team==1 and a.alive and not a.remembered and a.category=="unit")
 for enemy in enemies:
  if not enemy.id in hostile_ids:hostile_ids.append(enemy.id)
  if enemy.hp<enemy.max_hp:visible_hostile_damage[enemy.id]=enemy.max_hp-enemy.hp
 if not enemies.is_empty() and not military.is_empty() and g.tick_count-say_war>120:
  enemies.sort_custom(func(a,b):return a.pos.distance_squared_to(FRONT)<b.pos.distance_squared_to(FRONT))
  var target=enemies[0]
  g._submit("order",{"ids":military.map(func(q):return q.id),"target":target.id,"position":target.pos})
  contacts+=1;say_war=g.tick_count
 elif g.tick_count>=800 and g.tick_count-say_war>220:
  var ids=military.filter(func(q):return q.pos.distance_to(Vector3(-8.5,0,10.5))>8 and q.state=="idle").map(func(q):return q.id)
  if not ids.is_empty():g._submit("advance",{"ids":ids,"position":Vector3(-8.5,0,10.5)});say_war=g.tick_count
 if g.tick_count<340:return
 var w=g.faction_views[0].get_record(builder)
 if w.is_empty():return
 if build_tick<0:
  var p=choose_zone()
  if p.is_finite():
   g._submit("build",{"ids":[builder],"builder":builder,"position":p,"kind":"storehouse"})
   build_tick=g.tick_count
   print("ROUTE_DEPOT_PROPOSED ",p)
 if house<0:
  for r in known():
   if r.kind=="storehouse" and r.owned and r.built and zone(r.pos):
    house=r.id;print("ROUTE_DEPOT_COMPLETED ",g.tick_count," ",r.pos)
 if house<0:return
 for i in range(1,5):
  var id=team[i]
  var rec=g.faction_views[0].get_record(id)
  if rec.is_empty() or (last_order.has(id) and g.tick_count-last_order[id]<240):continue
  if rec.state not in ["idle","build"]:continue
  var anchor=FOOD_GOAL if i%2==0 else WOOD_GOAL
  var good=ordinary(id,anchor,["berry"] if i%2==0 else ["pine","oak"])
  if not good:ordinary(id,anchor)
  last_order[id]=g.tick_count
func run():
 root.size=Vector2i(390,844)
 var args=OS.get_cmdline_user_args()
 show_images=args.size()>=4 and DisplayServer.get_name()!="headless"
 if show_images:
  output_dir=args[0];requested_name=args[3]
  RenderingServer.render_loop_enabled=false
 shell=load("res://main_menu.tscn").instantiate()
 root.add_child(shell)
 await settle()
 for name in ["StartMatchButton","BattleGroup3","ChooseBattle_depot"]:await touch_by_name(name)
 check("actual grouped mode lands on new briefing",shell.page=="setup" and shell.selected_mode=="depot")
 await frame("briefing")
 await touch_by_name("LaunchMatchButton")
 await settle()
 g=shell.match_node
 assert(is_instance_valid(g) and g.skirmish_mode=="depot")
 g.history_path="/tmp/natural-depot-first-isolated-history.json"
 g.set_process(false);g.test_mode=true
 team=known().filter(func(r):return r.kind=="villager" and r.owned).map(func(r):return r.id)
 builder=team[1]
 ordinary(team[0],HOME_BERRY,["berry"])
 ordinary(builder,FRONT+Vector3(0,0,2))
 var scout=g._first(0,"scout")
 ordinary(scout.id,WOOD_GOAL+Vector3(0,0,3))
 for i in range(11000):
  note_phase()
  var prev={}
  for id in team:
   var w=g._get_entity(id)
   var c=g.economy.worker_view(id)
   if not w.is_empty() and w.state=="deliver" and c.cargo_milli>0:prev[id]=[w.target,c.cargo_type,c.cargo_milli,c.cargo_revision]
  g._tick(.05)
  for id in prev:
   var row=prev[id]
   var c=g.economy.worker_view(id)
   if c.cargo_milli!=0 or c.cargo_revision!=row[3]+1:continue
   var drop=g._get_entity(row[0])
   if drop.is_empty() or drop.kind not in ["town_center","storehouse"]:continue
   var line={"tick":g.tick_count,"destination":drop.id,"kind":drop.kind,"inside":zone(drop.pos),"resource":row[1],"amount_milli":row[2],"record":str(drop.pos)}
   witnesses.append(line)
   if row[1] in ["food","wood"]:
    var counts=depot_total if drop.id==house else home_total
    counts[row[1]]+=row[2]
   if drop.id==house:print("ROUTE_DELIVERY ",JSON.stringify(line))
  if not first_capture and g.forward_depot.totals.food>0 and g.forward_depot.totals.wood>0:
   first_capture=true
   check("ordinary home bank deliveries never inflated current mission score",home_total.food>0 and g.forward_depot.totals==depot_total)
   g._update_hud();await settle()
   await tap(g.objective_button.get_global_rect().get_center())
   check("real mission objective location touch shows supply site",g.camera_focus==Vector3(-11,0,15))
   g._update_visuals(.016);g._refresh_fog();g._update_hud();await settle()
   await frame("live-supply-run")
  if g.game_over:break
 var progress=g.forward_depot.report()
 g._update_visuals(.016);g._refresh_fog();g._update_hud();await settle()
 await frame("victory")
 var receipt={"scenario":"natural depot; menu routes/opening and ordinary paid commands","build":g._snapshot().build,"ticks":g.tick_count,"accounting":g.economy.audit().ok,"depot":depot_total,"home":home_total,"witnesses":witnesses,"mission":progress,"reported":g.last_match_report.get("forward_depot",{}),"won":g.game_over and g.outcome=="victory" and g.end_reason=="forward_depot_complete","built":g.match_report.completed,"trained":g.match_report.trained,"visible_hostile_damage":visible_hostile_damage,"hostile_observed":hostile_ids,"explicit_attacks":contacts,"actual_end_ui":g.end_title.text,"reason":g.end_reason}
 check("actual played match victory uses rule-specific end screen",receipt.won and receipt.actual_end_ui=="前線補給線建立")
 check("actual paid depot completed via normal warehouse construction",receipt.built.get("storehouse",0)==1)
 check("real garrison combat observed with ordinary explicit attacks",not visible_hostile_damage.is_empty() and contacts>=1 and not hostile_ids.is_empty())
 check("actual goal and paid receipts agree with mission final report",g.end_report_label.text.contains("前線倉庫交付") and receipt.reported==progress and progress.wood_milli==depot_total.wood and progress.food_milli==depot_total.food and depot_total.wood>=120000 and depot_total.food>=80000)
 check("all distinct real destination deliveries conserved",receipt.accounting and progress.deliveries==witnesses.filter(func(w):return w.destination==house).size())
 check("base deliveries existed and were excluded",home_total.food>0 and first_capture)
 check("standalone scenario not part of campaign or saves",g.campaign_chapter<0 and not FileAccess.file_exists(g.history_path))
 if show_images:check("official pack identity matches actual rendered game",requested_name==receipt.build)
 var n=checks.filter(func(row):return not row.passed).size()
 receipt["suite"]="forward_depot_natural_journey";receipt["checks"]=checks;receipt["failed"]=n
 receipt["scope"]="New native match reached through real menu touch and played with ordinary player commands. Actual contact, debit, delivery and final result; no fixture authority edits."
 receipt["images"]=images
 if show_images:
  var file=FileAccess.open(output_dir+"/report.json",FileAccess.WRITE);file.store_string(JSON.stringify(receipt));file.close()
 print(JSON.stringify(receipt))
 g.queue_free();quit(0 if n==0 else 1)
