extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var checks=[]
var shot_dir=""
var image_fact={}
func save_completed():
 if DisplayServer.get_name()=="headless":return
 await process_frame
 await process_frame
 await RenderingServer.frame_post_draw
 var frame=root.get_texture().get_image()
 var path=shot_dir+"/all-three-complete.png"
 if not frame.is_empty() and frame.save_png(path)==OK:image_fact={"width":frame.get_width(),"height":frame.get_height(),"sha256":FileAccess.get_sha256(path)}

func check(n,b):checks.append({"name":n,"passed":bool(b)})
const EscortMission=preload("res://scripts/frontier_escort.gd")
const ESCORT_HOME=Vector3(-25,0,24)
var departed=false
var counter_identity=[]
var counter_launches=0
var escort_game
var start=0
var orders=0
var events=[]
var last_stage=-1
var builder=-1
var battle_goal=Vector3.INF
var last_army_order=-1000
var last_build=-1000
func escort_submit(kind,data):
 escort_game._submit(kind,data);orders+=1
func escort_owned(records,kind):
 return records.filter(func(r):return r.get("owned",false) and r.get("alive",false) and r.get("kind","")==kind)
func escort_affordable(kind,bank):
 for key in Rules.COSTS[kind]:
  if bank.get(key,0)<Rules.COSTS[kind][key]*1000:return false
 return true
func escort_plot(kind,worker):
 for radius in [4,6,8,10]:
  for offset in [Vector3(1,0,0),Vector3(0,0,-1),Vector3(-1,0,0),Vector3(0,0,1),Vector3(1,0,1),Vector3(1,0,-1)]:
   var p=escort_game._snap_build_position(kind,ESCORT_HOME+offset*radius)
   if escort_game._placement_reason(kind,p,0,worker.id).is_empty():return p
 return Vector3.INF
func escort_opening_decide():
 var records=escort_game.faction_views[0].records().values()
 var workers=escort_owned(records,"villager")
 var home=escort_owned(records,"town_center")
 if home.is_empty():return
 var bank=escort_game.economy.bank_milli(0)
 var army=records.filter(func(r):return r.get("owned",false) and r.get("alive",false) and r.get("kind","") in ["spearman","archer","cavalry","siege"])
 var population=0;var capacity=0
 for r in records:
  if not r.get("owned",false) or not r.get("alive",false):continue
  if r.category=="unit":population+=1
  if r.category=="building":
   population+=r.get("queue",[]).filter(func(q):return not q.get("research",false)).size()
   if r.built:capacity+=10 if r.kind=="town_center" else (5 if r.kind=="house" else 0)
 var barracks=escort_owned(records,"barracks")
 var need=""
 if capacity-population<=2 and capacity<40:need="house"
 elif barracks.size()<2:need="barracks"
 # One ordinary build preview and command at a time; no site mutation.
 var unfinished=records.any(func(r):return r.get("owned",false) and r.category=="building" and not r.built)
 if need!="" and not unfinished and escort_game.tick_count-last_build>=100 and escort_affordable(need,bank):
  for w in workers:
   if w.state in ["build","repair"]:continue
   var p=escort_plot(need,w)
   if not p.is_finite():continue
   escort_submit("build",{"builder":w.id,"ids":[w.id],"kind":need,"position":p})
   builder=w.id;last_build=escort_game.tick_count;return
 if workers.size()<10 and home[0].queue.is_empty() and capacity>population and escort_affordable("villager",bank):
  escort_submit("train",{"building":home[0].id,"kind":"villager"});return
 for b in barracks:
  if b.built and b.queue.is_empty() and capacity>population and army.size()<24 and escort_affordable("spearman",bank):
   escort_submit("train",{"building":b.id,"kind":"spearman"});return
 for i in workers.size():
  var w=workers[i]
  if w.state not in ["idle"]:continue
  var food=i%3!=0
  var candidates=records.filter(func(r):return r.get("alive",false) and not r.get("remembered",true) and r.get("category","")=="resource" and (r.kind=="berry" if food else r.kind in ["pine","oak"]))
  candidates.sort_custom(func(a,b):return w.pos.distance_squared_to(a.pos)<w.pos.distance_squared_to(b.pos))
  if not candidates.is_empty():escort_submit("order",{"ids":[w.id],"target":candidates[0].id,"position":candidates[0].pos})

func escort_decide():
 var records=escort_game.faction_views[0].records().values()
 var army=records.filter(func(r):return r.get("owned",false) and r.get("alive",false) and r.get("kind","") in ["spearman","archer","cavalry","siege"])
 if not departed:
  if army.size()<14:escort_opening_decide();return
  departed=true
  escort_submit("order",{"ids":escort_game.frontier_escort.villagers.duplicate(),"position":EscortMission.TARGET})
  escort_submit("advance",{"ids":army.map(func(r):return r.id),"position":Vector3(-7,0,0)})
 var workers=escort_owned(records,"villager").filter(func(r):return r.id in escort_game.frontier_escort.villagers)
 if workers.is_empty():return
 var sites=records.filter(func(r):return r.get("owned",false) and r.get("alive",false) and r.get("kind","") in ["storehouse","tower"] and EscortMission.in_zone(r.pos))
 if not sites.any(func(r):return not r.built):
  var kind="storehouse" if not sites.any(func(r):return r.kind=="storehouse") else ("tower" if not sites.any(func(r):return r.kind=="tower") else "")
  if kind!="" and escort_affordable(kind,escort_game.economy.bank_milli(0)):
   for w in workers:
    for z in range(3,10):
     for x in range(-11,-2):
      var point=escort_game._snap_build_position(kind,Vector3(x,0,z))
      if escort_game._placement_reason(kind,point,0,w.id).is_empty():
       escort_submit("build",{"builder":w.id,"ids":[w.id],"kind":kind,"position":point});return
 # Issue only against visible enemies; otherwise hold the forward objective.
 var enemies=records.filter(func(r):return r.get("alive",false) and not r.get("remembered",true) and r.get("team",-1)==1 and r.category=="unit")
 if not enemies.is_empty():
  var target=enemies[0]
  var ids=army.filter(func(r):return r.state!="attack" or r.target!=target.id).map(func(r):return r.id)
  if not ids.is_empty():escort_submit("order",{"ids":ids,"target":target.id,"position":target.pos})
 else:
  var idle=army.filter(func(r):return r.state=="idle" and r.pos.distance_to(Vector3(-7,0,0))>5).map(func(r):return r.id)
  if not idle.is_empty():escort_submit("advance",{"ids":idle,"position":Vector3(-7,0,0)})

func _initialize():call_deferred("run")
func frames():
 for j in 4:await process_frame
func tap(button):
 if not is_instance_valid(button) or not button.is_visible_in_tree():return false
 var point=button.get_global_rect().get_center()
 for down in [true,false]:
  var ev=InputEventScreenTouch.new()
  ev.index=61;ev.position=point;ev.pressed=down
  root.push_input(ev)
  await process_frame
 return true
func owned(g,kind:String)->Array:
 return g.entities.filter(func(e):return e.alive and e.team==0 and e.kind==kind)
func available(g,key:String)->int:
 return int(g.economy.bank_milli(0).get(key,0)/1000)
func target_order(g,actor:Dictionary,target:Dictionary):
 g._submit("order",{"ids":[actor.id],"target":target.id,"position":target.pos})
func nearest(records:Array,origin:Vector3)->Dictionary:
 var best={};var d=INF
 for w in records:
  var next=w.pos.distance_squared_to(origin)
  if next<d:
   best=w;d=next
 return best
func improve_defense(g,tower_worker:Dictionary)->bool:
 if tower_worker.is_empty():return false
 var choices=[]
 # Add one tower on the near edge of the existing defense, not across
 # its center or at any specially known enemy spawn position.
 var desired=Vector3(-12,0,16)
 for x in range(-16,-8):
  for z in range(14,19):
   var p=Vector3(x,0,z)
   if p.distance_to(desired)<2.7 and g._placement_reason("tower",p,0,tower_worker.id)=="":choices.append(p)
 choices.sort_custom(func(a,b):return a.distance_squared_to(desired)<b.distance_squared_to(desired))
 if choices.is_empty():return false
 g._submit("build",{"kind":"tower","position":choices[0],"builder":tower_worker.id,"ids":[tower_worker.id]})
 return true
func opening(g)->bool:
 var workers=owned(g,"villager")
 if workers.size()<5:return false
 var records=g.faction_views[0].records()
 var gatherables=records.values().filter(func(e):return not e.get("remembered",false) and e.get("alive",false) and e.get("category","")=="resource")
 for i in range(1,5):
  var kinds=["oak","pine"] if i<=2 else ["berry"]
  var resource=nearest(gatherables.filter(func(e):return e.kind in kinds),workers[i].pos)
  if not resource.is_empty():target_order(g,workers[i],resource)
 for kind in ["barracks","range"]:
  var buildings=owned(g,kind)
  if not buildings.is_empty():
   var p=Vector3(-12,0,21) if kind=="barracks" else Vector3(-16,0,22)
   g._submit("rally",{"building":buildings[0].id,"position":p})
 return improve_defense(g,workers[0])
func sustain(g):
 var bank_food=available(g,"food")
 var bank_wood=available(g,"wood")
 var towers=owned(g,"tower")
 # Repairs only on current owned buildings, through the ordinary order and
 # affordability gates. During damage the engine can reject a repair.
 var workers=owned(g,"villager")
 if workers.size()>0 and bank_wood>=12:
  var sites=towers+owned(g,"town_center")
  sites.sort_custom(func(a,b):return float(a.hp)/a.max_hp<float(b.hp)/b.max_hp)
  for site in sites:
   if site.built and site.hp<site.max_hp*0.85 and g._repair_order_allowed(workers[0],site) and not workers.any(func(w):return w.state=="repair" and w.target==site.id):
    if workers[0].state not in ["build","repair"]:target_order(g,workers[0],site)
    break
 if g._population(0,true)>=g._capacity(0):return
 var range_buildings=owned(g,"range")
 var barracks=owned(g,"barracks")
 if bank_wood>=45 and bank_food>=25 and not range_buildings.is_empty() and range_buildings[0].queue.is_empty():
  g._submit("train",{"building":range_buildings[0].id,"kind":"archer"})
 if bank_wood>=65 and bank_food>=75 and not barracks.is_empty() and barracks[0].queue.is_empty():
  g._submit("train",{"building":barracks[0].id,"kind":"spearman"})
func observe_and_play(g):
 var seen=g.faction_views[0].records().values().filter(func(e):return e.get("team",-1)==1 and not e.get("remembered",false) and e.get("alive",false) and e.get("category","")=="unit")
 if seen.is_empty():return
 var keep=g._first(0,"town_center")
 if not keep.is_empty():
  var intruders=seen.filter(func(e):return e.pos.distance_to(keep.pos)<=16)
  for troop in g.faction_views[0].records().values():
   if not troop.get("owned",false) or not troop.get("alive",false) or troop.kind not in ["spearman","archer","cavalry","siege"]:continue
   if troop.state=="attack" and seen.any(func(e):return e.id==troop.target):continue
   var target=nearest(intruders,troop.pos)
   if not target.is_empty():target_order(g,troop,target)
 # Focus nearby siege with existing towers and current sight. No pursuit into
 # the fog, no formation teleport and no attack on remembered coordinates.
 for tower in owned(g,"tower"):
  var ram=nearest(seen.filter(func(e):return e.kind=="siege" and g._attack_distance(tower.pos,e)<=Rules.RANGE.tower),tower.pos)
  if not ram.is_empty() and tower.get("focus_target",-1)!=ram.id:
   g._submit("tower_focus",{"ids":[tower.id],"target":ram.id})
func submit_economic_orders(g):
 var worker=g._first(0,"villager")
 var barracks=g._first(0,"barracks")
 var choices=[]
 for x in range(-25,26):
  for z in range(-25,26):
   var candidate=Vector3(x,0,z)
   if g._placement_reason("house",candidate,0,worker.id)=="":choices.append(candidate)
 choices.sort_custom(func(a,b):return a.distance_squared_to(worker.pos)<b.distance_squared_to(worker.pos))
 check("ordinary orders use existing worker barracks and legal house site",not choices.is_empty() and not worker.is_empty() and not barracks.is_empty())
 if choices.is_empty():return false
 g._submit("build",{"kind":"house","position":choices[0],"builder":worker.id,"ids":[worker.id]})
 g._submit("train",{"building":barracks.id,"kind":"spearman"})
 return true
func run():
 var args=OS.get_cmdline_user_args()
 if args.size()!=4 or args[3]!=Rules.BUILD_ID:quit(1);return
 node_added.connect(func(n):
  if n.has_method("_check_end") and n.has_method("_update_vision") and n.has_method("_tick"):
   n.ready.connect(func():
    n.set_process(false)
    n.test_mode=true
   ,CONNECT_ONE_SHOT)
 )
 root.size=Vector2i(int(args[1]),int(args[2]));shot_dir=args[0]
 if DirAccess.make_dir_recursive_absolute(shot_dir)!=OK:quit(1);return
 var menu=load("res://main_menu.tscn").instantiate()
 root.add_child(menu);await frames()
 await tap(menu.buttons.get_node("StartMatchButton"))
 await frames()
 await tap(menu.buttons.get_node("CampaignMenuButton"))
 await frames()
 check("real start menu touch opens optional campaign without starting game",menu.page=="campaign" and not is_instance_valid(menu.match_node) and menu.description.text.contains("關閉網頁或重新整理"))
 if menu.page!="campaign":quit(1);return
 menu._choose_campaign(2)
 check("chapter three cannot bypass locked first chapter",menu.page=="campaign" and menu.campaign_unlocked==0 and not is_instance_valid(menu.match_node))
 await tap(menu.buttons.get_node("CampaignChapterButton"))
 await frames()
 check("first briefing does not start simulation",menu.page=="setup" and menu.selected_campaign==0 and not is_instance_valid(menu.match_node))
 if menu.page!="setup":quit(1);return
 await tap(menu.buttons.get_node("LaunchMatchButton"))
 if not is_instance_valid(menu.match_node):await process_frame
 if not is_instance_valid(menu.match_node):quit(1);return
 var g=menu.match_node
 g.set_process(false);g.test_mode=true
 check("launch opens authored siege campaign chapter",g.campaign_chapter==0 and g.skirmish_mode=="breach" and g.tick_count<4)
 menu._campaign_next()
 check("campaign cannot bypass unplayed current battle",menu.campaign_unlocked==0 and menu.match_node==g and not menu.menu_layer.visible)
 await process_frame
 var economic_orders=false
 var ids=[]
 for e in g.entities:
  if e.team==0 and e.category=="unit" and e.kind not in ["villager","scout"]:ids.append(e.id)
 var assigned={};var secondwall=-1;var thirdwall=-1;var phase=0;var wall_id=-1;var targets=[];var lasttarget=-1;var wall_crossed=false;var normal_damage=true;var checked_attack=1;var steps=[]
 g._submit("advance",{"ids":ids,"position":Vector3(6,0,-3)})
 for i in 6500:
  if g.game_over:break
  if i%20==0:
   var records=g.faction_views[0].records()
   var known=[]
   for e in records.values():
    if e.get("alive",false) and not e.get("remembered",false) and e.get("team",-1)==1:known.append(e)
   if phase==0 and ids.filter(func(id):return g._get_entity(id).kind=="siege").all(func(id):return g._get_entity(id).pos.distance_to(Vector3(6,0,-3))<7):
    for e in known:
     if e.kind=="wall" and e.pos==Vector3(0,0,-9):wall_id=e.id;phase=1;break
   var target=-1
   for e in known:
    if e.kind=="wall" and e.pos==Vector3(-2,0,-9):secondwall=e.id
    if e.kind=="wall" and e.pos==Vector3(2,0,-9):thirdwall=e.id
   if phase==1:
    if secondwall>=0 and thirdwall>=0 and not g._get_entity(wall_id).alive and not g._get_entity(secondwall).alive and not g._get_entity(thirdwall).alive:phase=2;steps.append({"wall_destroyed":g.tick_count});assigned.clear();g._submit("order",{"ids":ids,"target":-1,"position":Vector3(0,0,-10)})
    else:target=wall_id if g._get_entity(wall_id).alive else (secondwall if g._get_entity(secondwall).alive else thirdwall)
   if phase==2:
    if g.breach_mission.stage>=1:phase=3;steps.append({"post_destroyed":g.tick_count});assigned.clear();g._submit("advance",{"ids":ids,"position":Vector3(17,0,-15),"formation":"line"});lasttarget=-1
    else:
     for e in known:
      if e.id==g.breach_mission.post_id:target=e.id
   if phase==3:
    for e in known:
     if e.kind=="tower" and e.id!=g.breach_mission.post_id:target=e.id
    if target<0:
     for e in known:
      if e.kind=="town_center":target=e.id
   if phase==3 and target<0 and lasttarget>=0 and not g._get_entity(lasttarget).alive:
    g._submit("advance",{"ids":ids,"position":Vector3(25,0,-24)});lasttarget=-1;assigned.clear()
   for id in ids:
    var unit=g._get_entity(id)
    if not unit.alive or phase==0:continue
    # Let large actors physically enter the cleared breach before replacing
    # the movement with a tower attack. Shared sight is not arrival.
    if unit.kind in ["cavalry","siege"] and phase==2 and unit.pos.distance_to(Vector3(0,0,-10))>3:continue
    if unit.kind in ["cavalry","siege"] and phase==3 and unit.pos.distance_to(Vector3(17,0,-15))>10:continue
    var chosen=target
    if unit.kind!="siege" and (unit.kind=="archer" or phase>=2):
     var nearest=INF
     for e in known:
      if e.category=="unit" and e.pos.distance_squared_to(unit.pos)<nearest:
       chosen=e.id;nearest=e.pos.distance_squared_to(unit.pos)
    if chosen>=0 and chosen!=assigned.get(id,-1) and records.has(chosen) and not records[chosen].get("remembered",false):
     g._submit("order",{"ids":[id],"target":chosen,"position":records[chosen].pos});assigned[id]=chosen;lasttarget=chosen
     if chosen not in targets:targets.append(chosen)
  if phase==3 and not economic_orders:
   economic_orders=submit_economic_orders(g)
  g._tick(Rules.TICK)
  if phase>=2:
   for id in ids:
    var e=g._get_entity(id)
    if e.alive and e.pos.z<-9 and e.pos.distance_to(Vector3(0,0,-9))<3:wall_crossed=true
  for aid in range(checked_attack,g.attack_ledger.next_attack_id()):
   var event=g.attack_ledger.event(aid);var a=g._get_entity(event.attacker_id);var t=g._get_entity(event.target_id)
   if not a.is_empty() and not t.is_empty():normal_damage=normal_damage and event.damage==Rules.CONTENT.resolve_damage(a.kind,t.kind).damage
  checked_attack=g.attack_ledger.next_attack_id()
  if i%500==0:print("BREACH_TICK ",g.tick_count," phase=",phase," live=",ids.filter(func(id):return g._get_entity(id).alive).size()," target=",lasttarget," hp=",g._get_entity(lasttarget).get("hp",-1))
 check("normal commands destroyed front wall",wall_id>=0 and secondwall>=0 and thirdwall>=0 and not g._get_entity(wall_id).alive and not g._get_entity(secondwall).alive and not g._get_entity(thirdwall).alive)
 check("normal movement crosses broken wall",wall_crossed)
 check("ordinary damage equals shared rules",normal_damage and checked_attack>1)
 check("normal combat completed both objectives",g.breach_mission.stage==2 and g.game_over and g.outcome=="victory")
 check("mission economy AI stayed disabled by scenario not test flag",g.ai_enabled and g.ai_raids==0)
 var facts=g.match_report.events
 var completed=facts.filter(func(e):return e.action=="completed" and e.kind=="house")
 var born=facts.filter(func(e):return e.action=="trained" and e.kind=="spearman")
 var combat=facts.filter(func(e):return e.action=="contact")
 var overview=g.end_report_label.text
 check("actual paid ordinary construction reported",completed.size()==1 and g.match_report.completed.get("house",0)==1)
 check("actual paid ordinary barracks birth reported",born.size()==1 and g.match_report.trained.get("spearman",0)==1)
 check("actual player combat registered only once",combat.size()==1 and combat[0].tick>0 and combat[0].tick<g.tick_count)
 check("default victory modal displays real earned facts",g.end_panel.visible and g.end_title.text=="攻城突破完成" and overview.contains("首次完工") and overview.contains("首次出兵") and overview.contains("首次擊中敵方目標") and overview.contains(" · 勝利"))
 check("scenario-seeded age and siege never claimed as achieved",not overview.contains("完成研究 · 城防時代") and not overview.contains("首次攻城車出兵"))
 print("MILESTONE_SCREEN ",JSON.stringify({"overview":overview,"facts":facts,"tick":g.tick_count}))
 print("BREACH_MEMBERS ",ids.map(func(id):var e=g._get_entity(id);return {"id":id,"kind":e.kind,"alive":e.alive,"hp":e.hp,"pos":e.pos,"state":e.state,"path":e.path_status,"reason":e.path_reason,"dest":e.dest,"requested":e.path_request_goal,"resolved":e.path_resolved_goal}))
 print("BREACH_JOURNEY ",JSON.stringify({"tick":g.tick_count,"phase":phase,"stage":g.breach_mission.stage,"steps":steps,"targets":targets,"survivors":ids.filter(func(id):return g._get_entity(id).alive),"outcome":g.outcome}))
 check("actual first victory unlocks exactly chapter two",menu.campaign_unlocked==1 and g.end_setup_button.text=="下一場" and not menu.menu_layer.visible)
 check("victory button has forty four pixel touch target",g.end_setup_button.size.y>=44)
 var old_id=g.get_instance_id()
 var old_tick=g.tick_count
 var bank=g.economy.bank_milli(0)
 await frames()
 print("CAMPAIGN_NEXT_LAYOUT ",g.end_setup_button.get_global_rect()," ",root.get_visible_rect()," input ",g.all_touch_ids," ",g.touch_gesture)
 await tap(g.end_setup_button)
 await frames()
 check("real victory next button opens chapter two briefing only",menu.page=="setup" and menu.selected_campaign==1 and menu.match_node.get_instance_id()==old_id and menu.description.text.contains("三波"))
 if menu.page!="setup":quit(1);return
 await tap(menu.buttons.get_node("LaunchMatchButton"))
 if not is_instance_valid(menu.match_node) or menu.match_node.get_instance_id()==old_id:await process_frame
 var next=menu.match_node
 next.set_process(false);next.test_mode=true
 check("second launch loads authored survival independent from first",next.skirmish_mode=="survival" and next.campaign_chapter==1 and next.tick_count<12 and next.economy.bank_milli(0)!=bank and menu.campaign_unlocked==1)
 print("CAMPAIGN_OBSERVED ",JSON.stringify({"build":Rules.BUILD_ID,"chapter_one_won":old_tick,"unlocked":menu.campaign_unlocked,"active_chapter":next.campaign_chapter,"active_mode":next.skirmish_mode,"active_tick":next.tick_count,"chapter_two_victory":false,"chapter_three_victory":false}))
 var waves=[]
 var wave_ids=[]
 var clear_ticks=[]
 var tower_started=opening(next)
 var old_wave=0
 for i in 16000:
  if next.game_over or next.paused:break
  if i%80==0:sustain(next)
  if i%40==0:observe_and_play(next)
  next._tick(Rules.TICK)
  if next.siege_challenge.wave!=old_wave:
   old_wave=next.siege_challenge.wave;wave_ids=next.siege_challenge.active.duplicate()
   waves.append({"wave":old_wave,"tick":next.tick_count,"count":wave_ids.size()})
  if not wave_ids.is_empty() and next.siege_challenge.active.is_empty():
   clear_ticks.append({"tick":next.tick_count,"actual_deaths":wave_ids.all(func(id):return not next._get_entity(id).alive)});wave_ids.clear()
  if i%500==0:print("CAMPAIGN_SURVIVAL ",next.tick_count," waves=",next.siege_challenge.wave," active=",next.siege_challenge.active.size()," keep=",next._first(0,"town_center").get("hp",0))
 var next_win=next.game_over and next.outcome=="victory" and next.end_reason=="waves_defended"
 print("SURVIVAL_RESULT ",JSON.stringify({"complete":next_win,"tick":next.tick_count,"waves":waves,"clears":clear_ticks,"outcome":next.outcome,"reason":next.end_reason,"unlocked":menu.campaign_unlocked,"attack":next.attack_ledger.next_attack_id()-1,"tower_command":tower_started,"towers":next.match_report.completed.get("tower",0),"trained":next.match_report.trained}))
 if next_win:
  await frames()
  await tap(next.end_setup_button)
  await frames()
  check("genuine third-wave victory opens live escort setup",menu.page=="setup" and menu.selected_campaign==2 and menu.campaign_unlocked==2)
  if menu.page=="setup":
   var second_victory_tick=next.tick_count
   var next_old=next.get_instance_id()
   await tap(menu.buttons.get_node("LaunchMatchButton"))
   if menu.match_node.get_instance_id()==next_old:await process_frame
   var escort=menu.match_node
   escort.set_process(false);escort.test_mode=true
   check("genuine third chapter enters existing independent escort mode",escort.campaign_chapter==2 and escort.skirmish_mode=="escort" and escort.frontier_escort.stage==0)
   print("ESCORT_LAUNCHED ",JSON.stringify({"build":Rules.BUILD_ID,"tick":escort.tick_count,"stage":escort.frontier_escort.stage,"mode":escort.skirmish_mode,"unlocked":menu.campaign_unlocked,"contact":false,"outcome":escort.outcome}))
   escort_game=escort
   var escort_wall=Time.get_ticks_msec()
   var escort_stages=[]
   var prior=-1
   var launched_count=0
   var offered=[]
   while not escort.game_over and not escort.paused and escort.tick_count<15000 and Time.get_ticks_msec()-escort_wall<240000:
    if escort.tick_count%100==0:escort_decide()
    escort._tick(Rules.TICK)
    if escort.frontier_escort.stage!=prior:
     prior=escort.frontier_escort.stage
     var row={"stage":prior,"tick":escort.tick_count,"trained":escort.match_report.trained,"built":escort.match_report.completed}
     escort_stages.append(row)
     print("FULL_CAMPAIGN_ESCORT_STAGE ",JSON.stringify(row))
    if escort.frontier_escort.launched and escort.frontier_escort.counter_ids!=offered:
     offered=escort.frontier_escort.counter_ids.duplicate();launched_count+=1
   var clean=escort.economy.audit().ok
   var actual_victory=escort.game_over and escort.outcome=="victory" and escort.end_reason=="escort_complete" and escort.frontier_escort.stage==3
   check("ordinary escort pays for real buildings and visibly defends settlers",actual_victory and escort.match_report.completed.get("storehouse",0)>=1 and escort.match_report.completed.get("tower",0)>=1 and clean and launched_count==1 and escort.frontier_escort.living>=1)
   check("actual final objective earns campaign completion exactly once",actual_victory and menu.campaign_unlocked==3 and escort.end_setup_button.text=="戰役完成")
   print("FULL_CAMPAIGN_ESCORT_RESULT ",JSON.stringify({"build":Rules.BUILD_ID,"finished":escort.game_over,"outcome":escort.outcome,"reason":escort.end_reason,"ticks":escort.tick_count,"stage_ticks":escort.frontier_escort.stage_ticks,"party_survivors":escort.frontier_escort.living,"counter_launches":launched_count,"economy_audit":clean,"orders":orders,"chapters_done":menu.campaign_unlocked}))
   if actual_victory:
    await frames()
    await tap(escort.end_setup_button);await frames()
    check("real final result touch shows all three chapters done",menu.page=="campaign" and menu.description.text.contains("已完成 3 / 3"))
    if menu.page=="campaign" and menu.campaign_unlocked==3:
     await save_completed()
     var receipt=FileAccess.open(shot_dir+"/report.json",FileAccess.WRITE)
     receipt.store_string(JSON.stringify({"build":Rules.BUILD_ID,"complete":checks.all(func(x):return x.passed),"checks":checks,"victories":[old_tick,second_victory_tick,escort.tick_count],"campaign_completed":menu.campaign_unlocked,"settlers_alive":escort.frontier_escort.living,"counter_launches":launched_count,"image":image_fact}))
     receipt.close()

 menu.free();await process_frame
 print(JSON.stringify({"suite":"campaign_three_chapter_natural_audit","checks":checks,"failed":checks.filter(func(c):return not c.passed).size(),"scope":"Exact-runtime native sequential campaign attempts using actual menu touches and ordinary player commands; no forced state, no browser or iPhone acceptance."}))
 quit(1 if checks.any(func(c):return not c.passed) else 0)
