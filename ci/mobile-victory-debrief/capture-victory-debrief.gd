extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var checks=[]
var evidence={}
var gestures=0
var out=""
var info={}
var captured=[]
var metadata_only=false
var capture_role=""
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
 print("VC_CAPTURE_BOOT compact_debrief")
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
func report_snap(g):
 var box=g.end_scroll.get_global_rect()
 var body=g.end_body.get_global_rect()
 var label=g.end_report_label.get_global_rect()
 var f=g.end_report_label.get_theme_font("font")
 var line_px=f.get_height(g.end_report_label.get_theme_font_size("font_size"))+g.end_report_label.get_theme_constant("line_spacing")
 var bar=g.end_scroll.get_v_scroll_bar()
 var visible_label=label.intersection(box)
 var visible_body=body.intersection(box) if g.end_body.is_visible_in_tree() else Rect2()
 var actions={}
 for btn in g.end_actions.get_children():
  actions[btn.text]={"rect":rect(btn),"reached":reached(btn)}
 var visible_report_rows=[]
 for i in g.end_report_label.text.split("\n").size():
  var row=Rect2(Vector2(label.position.x,label.position.y+i*line_px),Vector2(label.size.x,line_px))
  if box.encloses(row):visible_report_rows.append(g.end_report_label.text.split("\n")[i])
 return {"title":g.end_title.text,"body":g.end_body.text,"report_text":g.end_report_label.text,"page":g.end_report_page,"panel":rect(g.end_panel),"title_rect":rect(g.end_title),"tabs_rect":rect(g.end_tabs),"body_rect":rect(g.end_body),"body_wrapped_lines":g.end_body.get_line_count(),"report_rect":rect(g.end_report_label),"report_wrapped_lines":g.end_report_label.get_line_count(),"scroll_rect":rect(g.end_scroll),"body_visible":g.end_body.is_visible_in_tree(),"body_px_visible":visible_body.size.y,"report_px_visible":visible_label.size.y,"vbar_visible":bar.is_visible_in_tree(),"scroll_px":g.end_scroll.scroll_vertical,"max_scroll":bar.max_value-bar.page,"line_px":line_px,"actions":actions,"visible_report_rows":visible_report_rows}

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
  if not ck(name+" two actual renderer frame completions",draws[0]>=2):return false
  checkpoint("readback_begin",{"state":name})
  var img=root.get_texture().get_image()
  checkpoint("readback_end",{"state":name,"valid":img!=null})
  if not ck(name+" actual native image dimensions",img!=null and not img.is_empty() and img.get_size()==Vector2i(568,320)):return false
  var palette={}
  for y in range(0,320,13):
   for x in range(0,568,13):palette[img.get_pixel(x,y).to_rgba32()]=true
  if not ck(name+" real native unmodified view is nonblank",palette.size()>24):return false
  state.file=name+".png"
  var path=out+"/"+state.file
  if not ck(name+" native PNG saved",img.save_png(path)==OK):return false
  state.sha256=FileAccess.get_sha256(path)
  checkpoint("png_saved",{"state":name,"sha256":state.sha256})
 captured.append(state)
 return true


func evidence_finish(menu):
 var expected=1 if capture_role=="baseline" else 2
 check("every planned state captured exactly once",captured.size()==expected)
 info.failed=checks.filter(func(c):return not c.passed).size()
 info.checks=checks;info.frames=captured;info.assertions=checks.size();info.evidence=evidence;info.gestures=gestures
 info.png_count=captured.filter(func(x):return x.has("sha256")).size()
 info.result="FAIL" if info.failed else ("METADATA_ONLY" if metadata_only else "RENDERED")
 checkpoint("finish",{"states":captured.size(),"failed":info.failed,"assertions":info.assertions,"gestures":gestures,"png_count":info.png_count})
 var f=FileAccess.open(out+"/report.json",FileAccess.WRITE)
 if f==null:quit(2);return
 f.store_string(JSON.stringify(info,"  "));f.close()
 if is_instance_valid(menu):menu.free()
 quit(1 if info.failed else 0)

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
 RenderingServer.render_loop_enabled=false
 var args=OS.get_cmdline_user_args()
 if args.size() not in [6,7] or args[1] not in ["baseline","candidate"] or (args.size()==7 and args[6]!="--metadata-only"):quit(2);return
 out=args[0];capture_role=args[1];metadata_only=args.size()==7
 if not out.begins_with("/") or DirAccess.dir_exists_absolute(out) or FileAccess.file_exists(out) or DirAccess.make_dir_recursive_absolute(out)!=OK:quit(2);return
 root.size=Vector2i(568,320)
 await frames()
 info={"scope":"Actual fresh authored Chapter 1 Breach combat via ordinary harness commands. Actual routed menu, objective and Buildings-tab synthetic touches; no injected economy, units, positions, report, fog, or outcome. Native 568x320, not public Web or iPhone.","build":Rules.BUILD_ID,"role":capture_role,"size":[568,320],"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"video_adapter":RenderingServer.get_video_adapter_name(),"game_sha":FileAccess.get_sha256("res://scripts/game.gd"),"rules_sha":FileAccess.get_sha256("res://scripts/rules.gd"),"report_sha":FileAccess.get_sha256("res://scripts/match_report.gd"),"metadata_only":metadata_only}
 checkpoint("initialize",{"build":info.build,"role":capture_role,"display":info.display})
 if not check("exact game scripts, build, engine mode and native 568x320",info.build==args[2] and info.game_sha==args[3] and info.rules_sha==args[4] and info.report_sha==args[5] and root.size==Vector2i(568,320) and (metadata_only or info.display!="headless")):evidence_finish(null);return
 var menu=load("res://main_menu.tscn").instantiate()
 parked_menu=menu
 var pg=preload("res://scripts/campaign_progress.gd")
 menu.campaign_progress_path="user://mission-probe-progress.json"
 menu.history_path="user://mission-probe-history.json"
 root.add_child(menu);await frames()
 check("start match visible 44px touch",await menu_tap(menu,"StartMatchButton"))
 await frames()
 check("campaign menu visible 44px touch via normal scroll if needed",await menu_tap(menu,"CampaignMenuButton"))
 await frames()
 check("real start menu touch opens optional campaign without starting game",menu.page=="campaign" and not is_instance_valid(menu.match_node) and menu.description.text.contains("未完成戰場不會恢復"))
 if menu.page!="campaign":evidence_finish(menu);return
 menu._choose_campaign(2)
 check("chapter three cannot bypass locked first chapter",menu.page=="campaign" and menu.campaign_unlocked==0 and not is_instance_valid(menu.match_node))
 check("Chapter 1 visible 44px touch via normal scroll",await menu_tap(menu,"CampaignChapterButton"))
 await frames()
 check("first briefing does not start simulation",menu.page=="setup" and menu.selected_campaign==0 and not is_instance_valid(menu.match_node))
 if menu.page!="setup":evidence_finish(menu);return
 check("Launch visible 44px touch via normal scroll",await menu_tap(menu,"LaunchMatchButton"))
 if not is_instance_valid(menu.match_node):await process_frame
 if not is_instance_valid(menu.match_node):evidence_finish(menu);return
 var g=menu.match_node
 g.set_process(false)
 g.history_path=menu.history_path
 g._process(0);g._update_hud();g._layout_ui()
 await frames()
 check("ordinary campaign runs normal effect/history mode in isolated user profile",not g.test_mode)
 if not is_instance_valid(g.objective_button):check("stage one objective button exists",false);evidence_finish(menu);return
 check("launch opens authored siege campaign chapter",g.campaign_chapter==0 and g.skirmish_mode=="breach" and g.tick_count==0)
 menu._campaign_next()
 check("campaign cannot bypass unplayed current battle",menu.campaign_unlocked==0 and menu.match_node==g and not menu.menu_layer.visible)
 await process_frame
 var opening_seq=g.command_sequence
 var opening_cam=g.camera_focus
 checkpoint("authored_chapter_launched",{"tick":g.tick_count,"bank":g.economy.bank_milli(0),"camera":str(opening_cam)})
 var first_objective={"text":g.objective_button.text,"rect":rect(g.objective_button),"camera_start":str(opening_cam),"button_full44":reached(g.objective_button)}
 var shot=await tap(g.objective_button);await frames()
 first_objective.after=str(g.camera_focus);first_objective.tap_succeeded=shot;first_objective.no_order=opening_seq==g.command_sequence
 evidence.first_objective=first_objective
 print("FIRST_MISSION_OBJECTIVE ",JSON.stringify(first_objective))
 var phase_one_hud=false
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
  if phase==3 and not phase_one_hud:
   phase_one_hud=true
   g._process(0);g._update_hud();g._layout_ui()
   await frames()
   var seq=g.command_sequence;var cash=g.economy.bank_milli(0)
   var stage_one={"stage_tick":g.breach_mission.stage_ticks[0],"text":g.objective_button.text,"rect":rect(g.objective_button),"before":str(g.camera_focus),"button_full44":reached(g.objective_button)}
   stage_one.tapped=await tap(g.objective_button)
   await frames()
   stage_one.after=str(g.camera_focus);stage_one.no_order=seq==g.command_sequence and cash==g.economy.bank_milli(0)
   evidence.second_objective=stage_one
   print("SECOND_MISSION_OBJECTIVE ",JSON.stringify(stage_one))
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
  if i%500==0:checkpoint("authored_breach_tick",{"tick":g.tick_count,"phase":phase,"live":ids.filter(func(id):return g._get_entity(id).alive).size(),"target":lasttarget,"hp":g._get_entity(lasttarget).get("hp",-1)})
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
 evidence.earned_facts=facts.duplicate(true)
 evidence.wall_path_steps=steps
 evidence.survivors=ids.filter(func(id):return g._get_entity(id).alive)
 checkpoint("authored_victory",{"tick":g.tick_count,"phase":phase,"stage":g.breach_mission.stage,"outcome":g.outcome,"survivors":evidence.survivors})
 var record=pg.read(menu.campaign_progress_path)
 check("actual first victory unlocks exactly chapter two",menu.campaign_unlocked==1 and g.end_setup_button.text=="下一場" and not menu.menu_layer.visible and record.ok and record.completed==1 and record.revision==1)
 check("victory button has forty four pixel touch target",g.end_setup_button.size.y>=44)
 g._process(0);g._layout_ui();await frames()
 var default_report=report_snap(g)
 evidence.objective_ticks=g.breach_mission.stage_ticks.duplicate()
 var persisted=History.read_history(menu.history_path)
 var real_report=g.last_match_report
 if not check("ordinary history persisted exactly one real win",g.history_write_status.ok and persisted.ok and persisted.entries.size()==1 and persisted.entries[0].outcome=="victory"):evidence_finish(menu);return
 evidence.saved_pages=persisted.entries[0].pages
 evidence.result={ "tick":g.tick_count,"outcome":g.outcome,"reason":g.end_reason,"selected":g.selected.duplicate(),"camera":str(g.camera.global_transform),"camera_focus":str(g.camera_focus),"zoom":g.camera_zoom,"map":g.layout_id,"command_sequence":g.command_sequence,"bank":g.economy.bank_milli(0),"trained":real_report.trained,"completed":real_report.completed,"unit_losses":real_report.unit_losses,"building_losses":real_report.building_losses,"unlocked":record.completed }
 if not check("expected exact ordinary result before opening report",g.tick_count==4590 and g.breach_mission.stage_ticks==[2254,4590] and g.end_reason=="breach_complete" and g.commands.is_empty() and end_controls_reached(g)):evidence_finish(menu);return
 if not check("original victory heading and full explanation precede scroll",default_report.title=="攻城突破完成" and default_report.body_visible and default_report.body.contains("前哨箭塔及敵方主堡已摧毀") and default_report.body_px_visible==default_report.body_rect[3] and default_report.scroll_px==0 and default_report.page=="overview"):evidence_finish(menu);return
 var compact=capture_role=="candidate"
 if not check("exact before/after Overview geometry and earned first line",default_report.scroll_rect[3]==(116 if compact else 64) and default_report.report_px_visible==(55 if compact else 3) and default_report.visible_report_rows==(["本局階段紀錄","00:18 · 首次擊中敵方目標"] if compact else [])):evidence_finish(menu);return
 if not check("capture victory and Next have legitimately rendered engine font metrics",fully_fitted(g.end_title) and fully_fitted(g.end_setup_button)):evidence_finish(menu);return
 default_report.tick=g.tick_count
 var name="before-victory-overview" if not compact else "after-victory-overview"
 if not await real_frame(name,default_report):evidence_finish(menu);return
 if not compact:evidence_finish(menu);return
 var tab
 for b in g.end_tabs.get_children():
  if b.get_meta("report_page")=="buildings":tab=b;break
 var sequence=g.command_sequence
 var camera=g.camera.global_transform
 var selection=g.selected.duplicate()
 if not check("one genuine fully visible Buildings tab touch",await tap(tab)):evidence_finish(menu);return
 await frames()
 var construction=report_snap(g)
 construction.tick=g.tick_count
 if not check("actual Houses row immediately visible, no repeated intro, same report and no Next",construction.page=="buildings" and "民居　1／0" in construction.visible_report_rows and not construction.body_visible and construction.scroll_px==0 and construction.report_px_visible==116 and construction.report_text==evidence.saved_pages.buildings and g.last_match_report==real_report and g.tick_count==default_report.tick and g.command_sequence==sequence and g.camera.global_transform==camera and g.selected==selection and menu.match_node==g and not menu.menu_layer.visible and end_controls_reached(g)):evidence_finish(menu);return
 await real_frame("after-victory-buildings",construction)
 evidence_finish(menu)

func end_controls_reached(g):
 var children=g.end_actions.get_children()
 if children.size()!=4 or not reached(g.end_setup_button):return false
 var r=g.end_panel.get_global_rect()
 return children.all(func(x):return reached(x) and fully_fitted(x) and r.encloses(x.get_global_rect()))

func fully_fitted(control):
 var font=control.get_theme_font("font")
 for c in control.text:
  if c!="\n" and not font.has_char(c.unicode_at(0)):return false
 var margin=16 if control is Button else 0
 return font.get_string_size(control.text,HORIZONTAL_ALIGNMENT_LEFT,-1,control.get_theme_font_size("font_size")).x+margin<=control.size.x
