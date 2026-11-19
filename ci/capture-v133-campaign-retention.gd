extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(n,b):checks.append({"name":n,"passed":bool(b)})
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
 root.size=Vector2i(int(args[1]),int(args[2]))
 if DirAccess.make_dir_recursive_absolute(args[0])!=OK:quit(1);return
 var menu=load("res://main_menu.tscn").instantiate()
 var pg=preload("res://scripts/campaign_progress.gd")
 menu.campaign_progress_path="/tmp/v133-natural-progress-"+str(Time.get_ticks_usec())+".json"
 root.add_child(menu);await frames()
 await tap(menu.buttons.get_node("StartMatchButton"))
 await frames()
 await tap(menu.buttons.get_node("CampaignMenuButton"))
 await frames()
 check("real start menu touch opens optional campaign without starting game",menu.page=="campaign" and not is_instance_valid(menu.match_node) and menu.description.text.contains("未完成戰場不會恢復"))
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
 var record=pg.read(menu.campaign_progress_path)
 check("actual first victory unlocks exactly chapter two",menu.campaign_unlocked==1 and g.end_setup_button.text=="下一場" and not menu.menu_layer.visible and record.ok and record.completed==1 and record.revision==1)
 check("victory button has forty four pixel touch target",g.end_setup_button.size.y>=44)
 var victory_tick=g.tick_count
 var path=menu.campaign_progress_path
 var report_victory=g.outcome=="victory" and g.end_reason=="breach_complete"
 menu.free();await frames()
 # Independent production controller must reconstruct the state solely from
 # the real separate local file that the previous genuine victory wrote.
 var fresh=load("res://main_menu.tscn").instantiate()
 fresh.campaign_progress_path=path
 root.add_child(fresh);await frames()
 check("fresh native controller reads persisted actual completion",fresh.campaign_unlocked==1 and fresh.campaign_storage.revision==1 and not is_instance_valid(fresh.match_node))
 await tap(fresh.buttons.get_node("StartMatchButton"));await frames()
 await tap(fresh.buttons.get_node("CampaignMenuButton"));await frames()
 check("fresh actual campaign UI offers chapter 2 only",fresh.page=="campaign" and fresh.description.text.contains("已完成 1 / 3") and fresh.buttons.get_node("CampaignChapterButton").text.contains("2") and not is_instance_valid(fresh.match_node))
 var image={}
 var passed=not checks.any(func(c):return not c.passed)
 if passed and DisplayServer.get_name()!="headless":
  await process_frame
  await RenderingServer.frame_post_draw
  var png=root.get_texture().get_image()
  var target=args[0]+"/campaign-progress-reopened.png"
  if png.is_empty() or png.save_png(target)!=OK:quit(1);return
  image={"width":png.get_width(),"height":png.get_height(),"sha256":FileAccess.get_sha256(target)}
 var proof={"build":Rules.BUILD_ID,"complete":passed,"checks":checks,"won":report_victory,"tick":victory_tick,"completed":fresh.campaign_unlocked,"revision":fresh.campaign_storage.revision,"image":image}
 var f=FileAccess.open(args[0]+"/report.json",FileAccess.WRITE)
 f.store_string(JSON.stringify(proof));f.close()
 DirAccess.remove_absolute(path);fresh.free()
 print("CAMPAIGN_REOPEN_CAPTURE ",JSON.stringify(proof))
 quit(0 if passed else 1)
