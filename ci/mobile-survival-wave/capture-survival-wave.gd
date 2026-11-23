extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var checks=[]
var evidence={}
var gestures=0
var out=""
var expect_status=false
var capture_role=""
var metadata_only=false
var capture_info={}
var captured=[]
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
 print("VC_CAPTURE_BOOT survival_wave")
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
func note(key,entry):
 evidence[key]=entry
 print("CHAPTER2_NOTE ",key," ",JSON.stringify(entry))
func alive_team(g,team,group):
 return g.faction_views[team].records().values().filter(func(r):return r.get("owned",false) and r.alive and r.kind in group)
func public_enemy(g,kinds):
 return g.faction_views[0].records().values().filter(func(r):return r.team==1 and r.alive and not r.get("remembered",false) and r.kind in kinds)
func sync(g):
 g._process(0);g._update_hud();g._layout_ui()
 await frames()
func box(v):
 return Rect2(Vector2(v[0],v[1]),Vector2(v[2],v[3]))
func effective_label_rect(node):
 if not node.is_visible_in_tree():return Rect2()
 var r=node.get_global_rect().intersection(root.get_visible_rect())
 var p=node.get_parent()
 while is_instance_valid(p):
  if p is ScrollContainer or (p is Control and p.clip_contents):r=r.intersection(p.get_global_rect())
  p=p.get_parent()
 return r
func wave_language(text):
 return text.contains("/ 3 波") or text.contains("波增援出發") or text.contains("三波增援全部") or text.contains("秒整備")
func live_status(g):
 var found=[]
 for node in g.ui.find_children("*","Control",true,false):
  if not (node is Label or node is Button) or not wave_language(node.text):continue
  var rr=effective_label_rect(node)
  if rr.has_area():
   found.append({"node":str(node.name),"text":node.text,"rect":[rr.position.x,rr.position.y,rr.size.x,rr.size.y]})
 return found
func status(g):
 var wave_label=g.ui.find_child("SurvivalWaveStatus",true,false)
 var wave_actual={}
 if is_instance_valid(wave_label):
  var wr=effective_label_rect(wave_label)
  wave_actual={"text":wave_label.text,"visible":wave_label.is_visible_in_tree(),"exact_rect":rect(wave_label),"clipped_rect":[wr.position.x,wr.position.y,wr.size.x,wr.size.y]}
 return {"wave_actual":wave_actual,"clock":g.time_label.text,"clock_rect":rect(g.time_label),"pause_button":rect(g.pause_button),"battle_alert_rect":rect(g.battle_jump_button) if g.battle_jump_button.is_visible_in_tree() else [],
         "tick":g.tick_count,"wave":g.siege_challenge.wave,"wave_active":not g.siege_challenge.active.is_empty(),
         "next_tick_model":g.siege_challenge.next_tick,"toast":g.toast_label.text if g.toast_label.is_visible_in_tree() else "",
         "mission_text":g.mission_label.text,"mission_visible":g.mission_label.is_visible_in_tree(),"mission_rect":rect(g.mission_label),
         "visible_wave_ui":live_status(g),"objective_button_visible":g.objective_button.is_visible_in_tree(),
         "landscape_world_cap":rect(g.hud_top),"menu_open":g.compact_menu.is_visible_in_tree(),"menu_surface":rect(g.compact_menu),"menu_button":rect(g.compact_menu_button),
         "keep_hp":g._first(0,"town_center").get("hp",0),"commands":g.command_sequence,"bank":g.economy.bank_milli(0)}
func check_preparation_panel(g,key):
 await sync(g)
 var detail={"closed":status(g)}
 var original_cam=g.camera.global_transform;var seq=g.command_sequence;var ids=g.selected.duplicate();var bank=g.economy.bank_milli(0);var tick=g.tick_count
 var opened=await tap(g.compact_menu_button);await sync(g)
 detail.open=status(g)
 detail.menu_tap=opened
 var b
 for btn in g.compact_menu.find_children("*","Button",true,false):
  if btn.text=="關閉" and reached(btn):b=btn;break
 detail.closed_again=await tap(b);await sync(g)
 detail.intact=g.command_sequence==seq and g.camera.global_transform==original_cam and g.selected==ids and g.economy.bank_milli(0)==bank and g.tick_count==tick
 check(key+" true Menu and true Close did not issue or change simulation/selection",detail.menu_tap and detail.closed_again and detail.intact and not g.compact_menu.is_visible_in_tree())
 var during=detail.closed.wave_actual
 var next=g.siege_challenge.wave+1
 var correct=(not during.is_empty() and during.visible and during.exact_rect==during.clipped_rect and during.text=="%d/3 整備45秒" % next) if expect_status else during.is_empty()
 check(key+" expected field status and original detailed menu unchanged",correct and not detail.closed.mission_visible and detail.open.mission_visible and not detail.open.visible_wave_ui.is_empty() and not detail.closed.objective_button_visible)
 note(key,detail)
func choose_visible_food(g):
 var villagers=alive_team(g,0,["villager"])
 var resources=g.faction_views[0].records().values().filter(func(r):return r.kind=="berry" and not r.get("remembered",false) and r.alive)
 if villagers.size()<2 or resources.is_empty():return false
 for i in 2:
  var w=villagers[i]
  resources.sort_custom(func(a,b):return a.pos.distance_squared_to(w.pos)<b.pos.distance_squared_to(w.pos))
  g._submit("order",{"ids":[w.id],"target":resources[mini(i,resources.size()-1)].id,"position":resources[mini(i,resources.size()-1)].pos})
 return true
func train_opening(g):
 var barracks=g._first(0,"barracks")
 var archery=g._first(0,"range")
 if barracks.is_empty() or archery.is_empty():return false
 g._submit("train",{"building":barracks.id,"kind":"spearman"})
 g._submit("train",{"building":archery.id,"kind":"archer"})
 g._submit("train",{"building":archery.id,"kind":"archer"})
 return true
func adapt_defense(g,wave,remembered_orders):
 # Only currently visible attackers and ordinary own units/geometry drive orders.
 # Wave 1 has no assisted military orders. Starting defenders and paid units fight normally.
 if wave<=1:return
 var hostile=public_enemy(g,["spearman","archer","siege","cavalry"])
 if hostile.is_empty():return
 var units=alive_team(g,0,["spearman","archer","siege","cavalry"])
 var tower=g._first(0,"tower")
 if tower.is_empty():tower=g._first(0,"town_center")
 if tower.is_empty():return
 for unit in units:
  if unit.pos.distance_to(tower.pos)>17:continue
  var near=hostile.duplicate()
  near.sort_custom(func(a,b):
   var offset_a=-49 if a.kind=="siege" and unit.kind in ["cavalry","siege"] else 0
   var offset_b=-49 if b.kind=="siege" and unit.kind in ["cavalry","siege"] else 0
   return a.pos.distance_squared_to(unit.pos)+offset_a<b.pos.distance_squared_to(unit.pos)+offset_b)
  var t=near[0]
  if t.pos.distance_to(unit.pos)>17 or remembered_orders.get(unit.id,-1)==t.id:continue
  remembered_orders[unit.id]=t.id
  g._submit("order",{"ids":[unit.id],"target":t.id,"position":t.pos})
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
  state.file=name+".png"
  var path=out+"/"+state.file
  if not check(name+" native PNG saved",img.save_png(path)==OK):return false
  state.sha256=FileAccess.get_sha256(path)
  checkpoint("png_saved",{"state":name,"sha256":state.sha256})
 captured.append(state)
 return true



func capture_stage(g,label,tick,text):
 var view=status(g)
 var actual=view.wave_actual
 var correct=(not actual.is_empty() and actual.visible and actual.exact_rect==actual.clipped_rect and actual.text==text) if expect_status else actual.is_empty()
 if not check("correct compared status with old toast entirely absent at tick "+str(tick),correct and g.tick_count==tick and not view.menu_open and view.toast.is_empty() and view.visible_wave_ui.is_empty()):return false
 if expect_status:
  var node=g.ui.find_child("SurvivalWaveStatus",true,false)
  var ft=node.get_theme_font("font")
  var fs=node.get_theme_font_size("font_size")
  var complete=true
  for ch in text:
   if not ft.has_char(ch.unicode_at(0)):complete=false
  if not check(label+" authored HUD font, whole text fits and neutral pointer",complete and fs==13 and ft.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x<=node.size.x and node.mouse_filter==Control.MOUSE_FILTER_IGNORE):return false
 view.camera=str(g.camera.global_transform)
 view.camera_focus=str(g.camera_focus)
 view.zoom=g.camera_zoom
 view.selection=g.selected.duplicate()
 view.active_ids=g.siege_challenge.active.duplicate()
 view.active_hp=g.siege_challenge.active.map(func(id):var e=g._get_entity(id);return {"id":id,"kind":e.kind,"alive":e.alive,"hp":e.hp,"pos":str(e.pos)})
 view.owned=g.faction_views[0].records().values().filter(func(e):return e.get("owned",false) and e.alive and e.team==0).map(func(e):return {"id":e.id,"pos":str(e.pos),"hp":e.get("hp",-1),"kind":e.kind})
 view.owned.sort_custom(func(a,b):return a.id<b.id)
 view.during_wave_context="active_final" if view.wave_active else "intermission"
 return await real_frame(label,view)

func finish(menu,g):
 check("two authored play states captured exactly once",captured.size()==2)
 check("matches all 19 original routed gestures",gestures==19)
 var failed=checks.filter(func(x):return not x.passed).size()
 var f=FileAccess.open(out+"/report.json",FileAccess.WRITE)
 if f==null:quit(2);return
 capture_info.failed=failed;capture_info.assertions=checks.size();capture_info.checks=checks;capture_info.gestures=gestures
 capture_info.frames=captured;capture_info.evidence=evidence
 capture_info.png_count=captured.filter(func(x):return x.has("sha256")).size()
 capture_info.result="FAIL" if failed else ("METADATA_ONLY" if metadata_only else "RENDERED")
 f.store_string(JSON.stringify(capture_info,"  "));f.close()
 checkpoint("finish",{"checks":checks.size(),"failed":failed,"gestures":gestures,"states":captured.size(),"png_count":capture_info.png_count})
 if is_instance_valid(menu):menu.free()
 quit(0 if failed==0 else 1)

func run():
 RenderingServer.render_loop_enabled=false
 var args=OS.get_cmdline_user_args()
 if args.size() not in [6,7] or args[1] not in ["baseline","candidate"] or (args.size()==7 and args[6]!="--metadata-only"):quit(2);return
 out=args[0];capture_role=args[1];expect_status=capture_role=="candidate";metadata_only=args.size()==7
 if not out.begins_with("/") or DirAccess.dir_exists_absolute(out) or FileAccess.file_exists(out) or DirAccess.make_dir_recursive_absolute(out)!=OK:quit(2);return
 root.size=Vector2i(568,320);await frames()
 capture_info={"scope":"Actual native 568x320 Chapter 2 after exact sanitized earned Chapter 1 test record. Ordinary authored waves, paid reinforcements and visible-target stock commands, 19 actual routed synthetic menu/drawer/Next touches. No injected enemies, funds, positions, outcome, overlay or compositing.","build":Rules.BUILD_ID,"role":capture_role,"size":[568,320],"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"video_adapter":RenderingServer.get_video_adapter_name(),"game_sha":FileAccess.get_sha256("res://scripts/game.gd"),"rules_sha":FileAccess.get_sha256("res://scripts/rules.gd"),"director_sha":FileAccess.get_sha256("res://scripts/siege_challenge.gd"),"metadata_only":metadata_only}
 checkpoint("initialize",{"build":capture_info.build,"role":capture_role,"display":capture_info.display})
 if not check("exact 568x320 and all three exact runtime sources",capture_info.build==args[2] and capture_info.game_sha==args[3] and capture_info.rules_sha==args[4] and capture_info.director_sha==args[5] and root.size==Vector2i(568,320) and (metadata_only or capture_info.display!="headless")):finish(null,null);return
 var menu=load("res://main_menu.tscn").instantiate();parked_menu=menu
 var pg=preload("res://scripts/campaign_progress.gd")
 menu.campaign_progress_path="user://isolated-survival-progress.json"
 menu.history_path="user://isolated-survival-history.json"
 var earned=pg.read(menu.campaign_progress_path)
 if not check("bootstrap is actual prior chapter one earned isolated record",earned.ok and earned.completed==1 and earned.revision==1):finish(menu,null);return
 root.add_child(menu);await frames()
 for n in ["StartMatchButton","CampaignMenuButton","CampaignChapterButton"]:
  if not check("real campaign menu touch "+n,await menu_tap(menu,n)):finish(menu,null);return
  await frames()
 if not check("earned Chapter 2 ordinary briefing states both legitimate win routes",menu.page=="setup" and menu.selected_campaign==1 and menu.description.text.contains("三波") and menu.description.text.contains("摧毀敵堡")):finish(menu,null);return
 note("briefing",{"description":menu.description.text,"setup":menu.short_setup_goal.text,"chapter":menu.selected_campaign})
 if not check("actual 44px Launch menu action",await menu_tap(menu,"LaunchMatchButton")):finish(menu,null);return
 if not is_instance_valid(menu.match_node):await process_frame
 var g=menu.match_node
 if not check("real Chapter 2 independent Survival begins at ordinary tick zero",is_instance_valid(g) and g.skirmish_mode=="survival" and g.campaign_chapter==1 and g.tick_count==0 and g.siege_challenge.wave==0 and not g.test_mode):finish(menu,g);return
 g.set_process(false);g.history_path=menu.history_path
 await check_preparation_panel(g,"opening_preparation_45s")
 var before=g.economy.bank_milli(0)
 check("ordinary existing visible berries and paid production available",choose_visible_food(g) and train_opening(g))
 var remembered_orders={};var launches=[];var clears=[];var checks_after={};var last_wave=0;var active=false;var natural_damage=0
 for cycles in 10500:
  if g.game_over or g.paused:break
  if g.tick_count%75==0 and active:adapt_defense(g,last_wave,remembered_orders)
  var pre=g.attack_ledger.next_attack_id()
  g._process(Rules.TICK)
  natural_damage+=g.attack_ledger.next_attack_id()-pre
  var wave=g.siege_challenge.wave
  var now_active=not g.siege_challenge.active.is_empty()
  if wave!=last_wave:
   last_wave=wave;remembered_orders.clear()
   await sync(g)
   var shown=status(g)
   launches.append({"wave":wave,"tick":g.tick_count,"roster":g.siege_challenge.active.map(func(id):return g._get_entity(id).kind),"status":shown})
   note("launch_"+str(wave),launches.back())
  if active and not now_active:
   var settled=status(g);clears.append({"wave":wave,"tick":g.tick_count,"status":settled})
   note("clear_"+str(wave),clears.back())
   if wave<3 and not g.game_over:
    if wave==1:
     await sync(g)
     if not await capture_stage(g,"intermission",2230,"2/3 整備45秒"):finish(menu,g);return
    await check_preparation_panel(g,"after_wave_"+str(wave)+"_45s")
    if wave==1:
     train_opening(g)
  if now_active and launches.size()>0 and g.tick_count==launches.back().tick+125:
   await sync(g)
   var expired=status(g);checks_after[str(wave)]=expired
   note("launch_notice_after_6_25s_"+str(wave),expired)
   var now=expired.wave_actual
   var correct=(not now.is_empty() and now.visible and now.exact_rect==now.clipped_rect and now.text==("3/3 最後一波" if wave==3 else "%d/3 迎擊" % wave)) if expect_status else now.is_empty()
   check("expected wave status survives the bounded launch toast: "+str(wave),expired.visible_wave_ui.is_empty() and not expired.mission_visible and expired.wave_active and correct)
   if wave==3 and not await capture_stage(g,"final-wave-after-toast",4985,"3/3 最後一波"):finish(menu,g);return
   if wave in [2,3]:
    var count_before=g.command_sequence;var tick_before=g.tick_count;var camera_before=g.camera.global_transform
    var opened=await tap(g.compact_menu_button);await sync(g)
    var actual=g.mission_label.text
    var expected="守城挑戰：第 3 / 3 波 · 最後一波；守住主堡並擊退增援。" if wave==3 and expect_status else "守城挑戰：第 %d / 3 波 · 擊退本波後有 45 秒整備；保護主堡。" % wave
    var m=effective_label_rect(g.mission_label)
    check("real active wave drawer has its exact expected full text: "+str(wave),opened and actual==expected and g.mission_label.is_visible_in_tree() and m==g.mission_label.get_global_rect())
    var b
    for btn in g.compact_menu.find_children("*","Button",true,false):
     if btn.text=="關閉" and reached(btn):b=btn;break
    var closed=await tap(b);await sync(g)
    check("actual drawer closed with no change to ordinary match during readout: "+str(wave),closed and not g.compact_menu.visible and g.command_sequence==count_before and g.tick_count==tick_before and g.camera.global_transform==camera_before)
    note("active_drawer_"+str(wave),{"wording":actual,"rect":[m.position.x,m.position.y,m.size.x,m.size.y],"tick":tick_before})
  if not now_active and wave in [1,2] and g.tick_count==g.siege_challenge.next_tick:
   await sync(g)
   var before_due=status(g)
   var expected_status="%d/3 待出發" % (wave+1)
   var original_tick=g.tick_count;var original_sequence=g.command_sequence
   var menu_when_due=await tap(g.compact_menu_button);await sync(g)
   var due_text=g.mission_label.text
   var expected_drawer="守城挑戰：第 %d / 3 波 · 待出發；可繼續整備。" % (wave+1) if expect_status else "守城挑戰：第 %d / 3 波將於 0 秒後抵達集結區；修塔、補兵、準備迎擊。" % (wave+1)
   var due_rect=effective_label_rect(g.mission_label)
   var right_hud=before_due.wave_actual.is_empty() if not expect_status else before_due.wave_actual.visible and before_due.wave_actual.text==expected_status
   check("actual unaligned due tick agrees with real open drawer and no wave has spawned: "+str(wave+1),menu_when_due and due_text==expected_drawer and due_rect==g.mission_label.get_global_rect() and right_hud and g.siege_challenge.active.is_empty() and g.tick_count==original_tick and g.command_sequence==original_sequence)
   var q
   for btn in g.compact_menu.find_children("*","Button",true,false):
    if btn.text=="關閉" and reached(btn):q=btn;break
   check("ordinary due drawer closes without gameplay order: "+str(wave+1),await tap(q));await sync(g)
   note("due_wave_"+str(wave+1),{"tick":g.tick_count,"wave_text":before_due.wave_actual,"drawer":due_text,"screen_fit":due_rect==g.mission_label.get_global_rect(),"commands":g.command_sequence})
  active=now_active
  if g.tick_count%500==0:checkpoint("ordinary_wave_progress",{"tick":g.tick_count,"wave":wave,"alive":g.siege_challenge.active.filter(func(id):return g._get_entity(id).alive).size(),"keep":g._first(0,"town_center").get("hp",0)})
 evidence.waves={"launches":launches,"clears":clears,"expired":checks_after,"damage_events":natural_damage}
 evidence.outcome={"end":g.game_over,"tick":g.tick_count,"paused":g.paused,"outcome":g.outcome,"reason":g.end_reason,"title":g.end_title.text,"keep_hp":g._first(0,"town_center").get("hp",0),"actual_paid":g.match_report.trained,"food_delivery":g.economy.stats_view(0).delivered.food,"opening_bank":before,"bank":g.economy.bank_milli(0)}
 note("terminal",evidence.outcome)
 check("three real reinforcement squads of 6 / 8 / 12 killed only by ordinary settled combat",launches.size()==3 and clears.size()==3 and launches.map(func(e):return e.roster.size())==[6,8,12] and natural_damage>0)
 check("player still holds keep after ordinary battles and complete Chapter 2 victory",g.game_over and g.outcome=="victory" and g.end_reason=="waves_defended" and not g._first(0,"town_center").is_empty())
 check("regular authored 900-tick preparation after first and second clear",clears.size()==3 and clears[0].status.next_tick_model==clears[0].tick+900 and clears[1].status.next_tick_model==clears[1].tick+900)
 if g.game_over and g.outcome=="victory":
  await sync(g)
  var terminal_status=status(g)
  check("terminal report has no active wave UI",terminal_status.wave_actual.is_empty() or not terminal_status.wave_actual.visible)
  evidence.final_status=terminal_status
  var updated=pg.read(menu.campaign_progress_path)
  var stored=History.read_history(menu.history_path)
  check("normal survival victory writes one local history and advances campaign to Chapter 3",updated.ok and updated.completed==2 and updated.revision==2 and stored.ok and stored.entries.size()==1 and g.history_write_status.ok and g.end_title.text=="三波守城成功" and g.end_setup_button.text=="下一場")
  var next_rect=rect(g.end_setup_button)
  check("actual Next press reaches genuine Chapter 3 briefing",await tap(g.end_setup_button));await frames()
  check("real Next only opens Chapter 3 Escort briefing and does not silently start",menu.page=="setup" and menu.selected_campaign==2 and menu.match_node==g and menu.description.text.contains("護送"))
  note("next",{"button":next_rect,"page":menu.page,"selected":menu.selected_campaign,"progress":updated.completed,"revision":updated.revision,"history_ok":stored.ok,"completed_match_retained":menu.match_node==g})
 finish(menu,g)
