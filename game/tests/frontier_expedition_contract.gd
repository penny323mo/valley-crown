extends SceneTree
const Mission=preload("res://scripts/frontier_expedition.gd")
const Store=preload("res://scripts/checkpoint_store.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var d=Mission.new()
 check("initial stores and gifted army do not satisfy production",not d.advance(0,0,0,true,false,false,false) and d.stage==0)
 check("food alone insufficient",not d.advance(1,1,100000,true,false,false,false))
 check("real production and deposited food advance only one stage",d.advance(2,2,100000,false,true,false,true) and d.stage==1)
 check("unknown outpost does not advance",not d.advance(3,2,100000,false,true,false,true))
 d.advance(4,2,100000,true,true,false,true)
 check("scouting enables assault objective",d.stage==2 and d.target()==Mission.OUTPOST)
 d.advance(5,2,100000,true,false,false,true)
 check("outpost death starts thirty second warning",d.stage==3 and not d.ready(604) and d.ready(605))
 check("empty wave is never auto completed",not d.advance(700,2,100000,true,false,false,true))
 check("partial reinforcements rejected",not d.launch([1]))
 check("wave accepted once",d.launch([1,2,3,4,5,6]) and not d.launch([1,2,3,4,5,6]))
 check("one survivor prevents clearing",not d.advance(701,2,100000,true,false,true,false))
 d.advance(702,2,100000,true,false,false,false)
 check("cleared wave exposes final keep objective",d.stage==4 and d.target()==Mission.ENEMY_HOME)
 d.advance(703,2,100000,true,false,false,false)
 check("all five stages recorded",d.stage==5 and d.stage_ticks==[2,4,5,702,703])
 var shell=load("res://scripts/main_menu.gd").new();root.add_child(shell);await process_frame
 check("home provides direct mission entry",shell.find_child("ExpeditionHomeButton",true,false)!=null)
 shell.find_child("ExpeditionHomeButton",true,false).pressed.emit()
 check("mission shortcut goes to setup not destructive launch",shell.page=="setup" and shell.selected_mode=="expedition" and not is_instance_valid(shell.match_node))
 check("scenario and unsupported save clearly disclosed",shell.description.text.contains("暫不支援存檔") and shell.description.text.contains("不消耗敵方資源"))
 shell.queue_free();await process_frame
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="expedition";root.add_child(g);g.set_process(false);g.test_mode=true;await process_frame
 check("scenario keeps ordinary player economy opening",g._count(0,"villager")==5 and g._count(0,"scout")==1 and g._count(0,"spearman")==0 and not g._age2(0))
 check("enemy is finite authored garrison not hidden economy",g._count(1,"villager")==0 and g._count(1,"tower")==2 and g._count(1,"spearman")==2)
 check("outpost begins unexplored",g.explored_cells[0][g._cell_index(Mission.OUTPOST)]==0)
 var seen=g.explored_cells[0].duplicate();g._focus_control_point()
 check("objective camera focus never reveals fog",g.explored_cells[0]==seen and g.camera_focus==Mission.HOME)
 g._update_hud()
 check("objective row visible",g.objective_button.visible and g.objective_button.text.contains("1/5"))
 var path="/tmp/campaign-preserve-test.bin";var f=FileAccess.open(path,FileAccess.WRITE);f.store_string("prior-save");f.close();g.paused=true
 var save=Store.save_slot(g,path)
 check("mission save refused before touching old slot",not save.ok and FileAccess.get_file_as_string(path)=="prior-save" and not FileAccess.file_exists(path+".tmp"))
 g.paused=false
 # Controlled funded fixture for actual production and deliveries, not balance.
 g._test_reset([{"food":1000,"wood":1000,"stone":1000,"iron":1000},{}]);g.set_process(false);g.ai_enabled=false
 var barracks=g._spawn("barracks",0,Vector3(-19,0,24),true)
 g._spawn("house",0,Vector3(-30,0,28),true);g._navigation_rebuild();g._update_vision()
 var before=g.economy.bank_milli(0).food
 check("normal paid production queues two soldiers",g._enqueue_train(barracks.id,"spearman",0) and g._enqueue_train(barracks.id,"spearman",0))
 check("production deducts actual resources",g.economy.bank_milli(0).food<before)
 for i in 1500:
  g.tick_count+=1;g._update_production(barracks,g.Rules.TICK,false);g._process_ready_production()
 g._update_frontier_expedition()
 check("trained soldiers recorded but food delivery still required",g.match_report.trained.get("spearman",0)==2 and g.frontier_expedition.stage==0)
 # Authority delivery methods tested separately; director integration uses frozen stats.
 # Do not invent income: actual nearby worker receives gather order and ticks.
 var worker=g._first(0,"villager");var berry={}
 for e in g.entities:
  if e.alive and e.kind=="berry":berry=e;break
 g._submit("order",{"ids":[worker.id],"position":berry.pos,"target":berry.id})
 for i in 8000:
  g._tick(.05)
  if g.frontier_expedition.stage==1:break
 check("real gathering deposits food and unlocks scouting",g.frontier_expedition.stage==1 and g.economy.stats_view(0).delivered.food>=100000)
 check("ledger conserves resources",g.economy.audit().ok)
 var scout=g._first(0,"scout")
 scout.pos=Mission.OUTPOST+Vector3(-5,0,0);g._update_vision();g._update_frontier_expedition()
 check("actual sight unlocks outpost assault",g.frontier_expedition.stage==2)
 # Death manipulation below is explicit state-machine fixture, not a full-play claim.
 g._kill(g._get_entity(g.frontier_expedition.outpost_id));g._update_frontier_expedition()
 check("destroyed authored outpost starts retaliation",g.frontier_expedition.stage==3 and not g.frontier_expedition.counter_launched)
 check("actual stage transition emits brief three second toast",g.toast_time==3 and g.toast_label.text=="前哨已攻破，30秒後反攻")
 g.tick_count=ceili(g.frontier_expedition.counter_due/20.0)*20
 g._update_frontier_expedition()
 check("real reinforcement entities and normal command created",g.frontier_expedition.counter_ids.size()==6 and g.commands.any(func(c):return c.type=="advance" and c.team==1 and c.ids==g.frontier_expedition.counter_ids))
 var enemy_bank=g.economy.bank_milli(1).duplicate();var count=g.entities.size();g._update_frontier_expedition()
 check("no duplicate reinforcement or counterfeit spending",g.entities.size()==count and g.economy.bank_milli(1)==enemy_bank and g.trained_total[1]==0)
 g._kill(g._first(1,"town_center"));g._check_end()
 check("early enemy keep kill cannot bypass live counterattack",not g.game_over)
 for id in g.frontier_expedition.counter_ids:g._kill(g._get_entity(id))
 g._update_frontier_expedition();g._update_frontier_expedition();g._check_end()
 check("mission win waits for all five objectives",g.game_over and g.outcome=="victory" and g.end_reason=="expedition_complete")
 check("result contains stage timeline",g.last_match_report.expedition.stage==5 and g.last_match_report.expedition.stage_ticks.size()==5 and g.MatchReport.page_text(g.last_match_report,"overview").contains("遠征階段"))
 g._test_reset();g.set_process(false)
 check("restart clears mission state",g.frontier_expedition.stage==0 and not g.frontier_expedition.counter_launched)
 g._kill(g._first(0,"town_center"));g._check_end()
 check("own keep loss remains defeat",g.game_over and g.outcome=="defeat")
 g._test_reset();g.set_process(false);g.frontier_expedition.stage=3;g.frontier_expedition.counter_due=0
 for y in g.Rules.MAP_SIZE:
  for x in g.Rules.MAP_SIZE:g.navigation.set_point_solid(Vector2i(x,y),true)
 g._update_frontier_expedition()
 check("blocked staging cannot force overlapping wave",not g.frontier_expedition.counter_launched and g.frontier_expedition.counter_ids.is_empty())
 g._test_reset();g.set_process(false);g.recovery_ticks[1]=g.EndRules.IRRECOVERABLE_TICKS;g._check_end()
 check("authored enemy cannot lose through economy shortcut",not g.game_over)
 g.recovery_ticks[0]=g.EndRules.IRRECOVERABLE_TICKS;g._check_end()
 check("stranded player still loses through recovery rule",g.game_over and g.outcome=="defeat" and g.end_reason=="irrecoverable")
 g._test_reset();g.set_process(false);g.tick_count=roundi(g.Rules.TIME_LIMIT/g.Rules.TICK);g._check_end()
 check("expedition retains time limit draw",g.game_over and g.outcome=="draw" and g.end_reason=="time_limit")
 g._test_reset();g.set_process(false);g._surrender_intent[0]=true;g._check_end()
 check("player surrender retains priority",g.game_over and g.outcome=="defeat" and g.end_reason=="surrender")
 g._test_reset();g.set_process(false)
 for size in [Vector2i(390,844),Vector2i(640,360)]:
  root.size=size;await process_frame
  g._layout_ui();g.compact_menu.hide()
  var tag="%dx%d" % [size.x,size.y]
  g.frontier_expedition.stage=0;g.frontier_expedition.supplied=40000;g.frontier_expedition.trained=1
  g._refresh_control_point_marker()
  check("touch objective shows exact economy progress "+tag,g.objective_button.visible and g.objective_button.text.contains("糧 40/100 · 軍人 1/2") and not g.compact_menu.visible)
  var rect=g.objective_button.get_global_rect()
  check("touch objective lies within viewport "+tag,Rect2(Vector2.ZERO,Vector2(size)).encloses(rect) and rect.size.y>=44)
  var font=g.objective_button.get_theme_font("font")
  var font_size=g.objective_button.get_theme_font_size("font_size")
  var width=g.objective_button.size.x-24
  check("economy objective text fits without clipping "+tag,font.get_string_size(g.objective_button.text.split("\n")[1],HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x<=width)
  g.frontier_expedition.stage=3;g.frontier_expedition.counter_launched=false;g.frontier_expedition.counter_due=g.tick_count+400
  g._refresh_control_point_marker()
  check("touch objective shows countdown without hover "+tag,g.objective_button.text.contains("反攻 20 秒後出發"))
  g.frontier_expedition.counter_due=g.tick_count
  g._refresh_control_point_marker()
  check("blocked staging explained on touch HUD "+tag,g.objective_button.text.contains("集結區受阻"))
  g.frontier_expedition.counter_launched=true;g.frontier_expedition.counter_ids=[g._first(1,"spearman").id]
  g._refresh_control_point_marker()
  check("touch objective shows remaining attackers "+tag,g.objective_button.text.contains("反攻餘下 1/6"))
  check("counter objective text fits without clipping "+tag,font.get_string_size(g.objective_button.text.split("\n")[1],HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x<=width)
 for size in [Vector2i(390,844),Vector2i(640,360)]:
  root.size=size;await process_frame
  g._layout_ui();g.compact_menu.hide();g.compact_menu_dismiss.hide()
  var tag="%dx%d" % [size.x,size.y]
  g.frontier_expedition.stage=2
  var explored=g.explored_cells[0].duplicate();var pending=g.commands.duplicate(true)
  g.objective_button.pressed.emit()
  check("objective remains pure location without overlay "+tag,g.camera_focus==Mission.OUTPOST and not g.compact_menu.visible and g.explored_cells[0]==explored and g.commands==pending)
  g._update_hud();g._toggle_compact_menu()
  await process_frame;await process_frame
  g.shortcut_scroll.ensure_control_visible(g.mission_label)
  await process_frame
  check("menu offers full touch readable mission instructions "+tag,g.compact_menu.visible and g.mission_label.text==g.frontier_expedition.caption(g.tick_count) and g.mission_label.is_visible_in_tree())
  var screen=Rect2(Vector2.ZERO,Vector2(size))
  check("mission menu remains inside viewport "+tag,screen.encloses(g.compact_menu.get_global_rect()))
  check("full instruction label fits scroll width "+tag,g.mission_label.size.x<=g.shortcut_scroll.size.x and g.shortcut_scroll.get_global_rect().intersects(g.mission_label.get_global_rect()))
  g._toggle_compact_menu()
  check("existing close restores battlefield "+tag,not g.compact_menu.visible and not g.compact_menu_dismiss.visible)
  var font=g.toast_label.get_theme_font("font");var font_size=g.toast_label.get_theme_font_size("font_size")
  var all_fit=true
  for stage in range(1,6):
   g.frontier_expedition.stage=stage
   var notice=g.frontier_expedition.transition_text()
   all_fit=all_fit and not notice.contains("\n") and font.get_string_size(notice,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x<=g.toast_label.size.x
  check("every transition notice fits one line "+tag,all_fit)
 g.queue_free();await process_frame
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"frontier_expedition_contract","checks":checks,"failed":failed,"scope":"Authored mission lifecycle plus real paid training and food delivery; scouting position and combat deaths controlled, not natural full mission/balance/mobile acceptance"}));quit(1 if failed else 0)
