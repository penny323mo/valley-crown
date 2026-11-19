extends SceneTree
const Battle=preload("res://scripts/battle_selection.gd")
const Rules=preload("res://scripts/rules.gd")
const Auto=preload("res://scripts/auto_checkpoint.gd")
const Store=preload("res://scripts/checkpoint_store.gd")
var checks=[]
func ck(n,x):checks.append({"name":n,"passed":bool(x)})
func frames():
 for _i in 4:await process_frame
func press(menu,id):
 menu.buttons.get_node(id).pressed.emit()
 await frames()
func running(menu):
 var g=menu.match_node
 g.set_process(false);g.test_mode=true
 return g
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(390,844)
 ck("generic surrender and irrecoverable victories do not unlock",not Battle.campaign_completed(1,"survival","victory","irrecoverable") and not Battle.campaign_completed(1,"survival","victory","surrender") and Battle.campaign_completed(1,"survival","victory","keep_destroyed"))
 var menu=load("res://main_menu.tscn").instantiate()
 var isolated="/tmp/v132-campaign-"+str(Time.get_ticks_usec())
 menu.checkpoint_path=isolated+"-manual"
 menu.expedition_checkpoint_path=isolated+"-expedition"
 menu.auto_checkpoint_path=isolated+"-auto"
 var paths=[menu.checkpoint_path,menu.expedition_checkpoint_path,menu.auto_checkpoint_path]
 for f in paths:
  var file=FileAccess.open(f,FileAccess.WRITE)
  file.store_string("isolated existing slot");file.close()
 root.add_child(menu);await frames()
 await press(menu,"StartMatchButton")
 var entry=menu.buttons.get_node("CampaignMenuButton")
 for size in [Vector2i(320,568),Vector2i(390,844),Vector2i(640,360)]:
  root.size=size;menu._layout();await frames()
  ck("campaign selector touch target fits "+str(size),root.get_visible_rect().encloses(entry.get_global_rect()) and entry.size.y>=44)
 root.size=Vector2i(390,844);menu._layout();await frames()
 await press(menu,"CampaignMenuButton")
 ck("clear session only and no army carryover",menu.description.text.contains("關閉網頁或重新整理") and menu.description.text.contains("資源與軍隊不帶到下一場"))
 await press(menu,"CampaignChapterButton");await press(menu,"LaunchMatchButton")
 var g=running(menu)
 g._submit("surrender");g._tick(Rules.TICK)
 ck("actual ordinary defeat cannot unlock stage",g.game_over and g.outcome=="defeat" and menu.campaign_unlocked==0 and g.end_setup_button.text=="戰役流程")
 var original=g.get_instance_id()
 g.end_actions.get_node("ReplayMatchButton").pressed.emit();await frames()
 g=running(menu)
 ck("retry keeps exact campaign mission and starts over",g.get_instance_id()!=original and g.skirmish_mode=="breach" and g.campaign_chapter==0 and g.tick_count<20 and g.breach_mission.stage==0 and menu.campaign_unlocked==0)
 # Explicit controlled terminal boundary for branches not covered by the natural screenshot journey.
 g.breach_mission.stage=2;g._check_end()
 ck("controlled authored first win unlocks chapter two once",g.outcome=="victory" and menu.campaign_unlocked==1 and g.end_setup_button.text=="下一場")
 menu._observe_campaign_result(g);g._check_end()
 ck("repeated old terminal signal cannot advance again",menu.campaign_unlocked==1)
 g.end_setup_button.pressed.emit();await frames()
 ck("next shows briefing and retains prior terminal match",menu.page=="setup" and menu.selected_campaign==1 and menu.match_node==g)
 await press(menu,"BackButton");await press(menu,"RestartCampaignButton")
 ck("restart preview does not discard progress before launch",menu.page=="setup" and menu.selected_campaign==0 and menu.campaign_unlocked==1)
 await press(menu,"BackButton")
 ck("cancel restart preserves earned next chapter",menu.page=="campaign" and menu.selected_campaign<0 and menu.campaign_unlocked==1)
 await press(menu,"CampaignChapterButton");await press(menu,"LaunchMatchButton")
 g=running(menu)
 ck("survival starts as the correct independent chapter",g.campaign_chapter==1 and g.skirmish_mode=="survival" and g.siege_challenge.wave==0 and menu.campaign_unlocked==1)
 # Check both public save entry points directly with different existing bytes.
 g.paused=true;menu.auto_checkpoint_enabled=true;menu._schedule_auto_checkpoint(g)
 ck("campaign chapter two manual and auto save refuse",not Store.save_slot(g,menu.checkpoint_path).ok and not Auto.save_slot(g,menu.auto_checkpoint_path).ok and menu.auto_checkpoint_pending=="")
 menu._open_menu();menu._show_page("checkpoint");await frames()
 ck("campaign checkpoint UI discloses no writing",not menu.buttons.has_node("SaveCheckpointButton") and menu.description.text.contains("不寫入存檔"))
 menu._resume_match();await frames();g=running(menu)
 g.siege_challenge.complete=true;g._check_end()
 ck("controlled authored survival victory unlocks escort only",g.outcome=="victory" and g.end_reason=="waves_defended" and menu.campaign_unlocked==2)
 g.end_setup_button.pressed.emit();await frames()
 ck("controlled victory routes to genuine escort briefing",menu.page=="setup" and menu.selected_campaign==2 and menu.description.text.contains("護送"))
 await press(menu,"LaunchMatchButton")
 g=running(menu);g.frontier_escort.stage=3;g._check_end()
 ck("controlled authored escort final victory closes the campaign",g.campaign_chapter==2 and g.end_reason=="escort_complete" and g.outcome=="victory" and menu.campaign_unlocked==3 and g.end_setup_button.text=="戰役完成")
 g.end_setup_button.pressed.emit();await frames()
 ck("completion shows three done and does not auto create a new match",menu.page=="campaign" and menu.description.text.contains("已完成 3 / 3") and not menu.buttons.has_node("CampaignChapterButton") and menu.match_node==g)
 await press(menu,"RestartCampaignButton");await press(menu,"LaunchMatchButton")
 g=running(menu)
 ck("explicit restart launch resets progression only then",g.skirmish_mode=="breach" and g.campaign_chapter==0 and menu.campaign_unlocked==0)
 g._submit("surrender");g._tick(Rules.TICK)
 menu._open_menu();menu._show_page("battle_groups");await frames()
 await press(menu,"BattleGroup3");await press(menu,"ChooseBattle_breach");await press(menu,"LaunchMatchButton")
 g=running(menu)
 g.breach_mission.stage=2;g._check_end()
 ck("standalone scenario still has original result and no unlock",g.outcome=="victory" and g.campaign_chapter==-1 and g.end_setup_button.text=="重新設定" and menu.campaign_unlocked==0)
 ck("ordinary expedition and auto files all remain byte exact",paths.all(func(p):return FileAccess.get_file_as_string(p)=="isolated existing slot"))
 menu.free()
 var fresh=load("res://main_menu.tscn").instantiate();root.add_child(fresh);await frames()
 ck("fresh page session has no silently restored progression",fresh.campaign_unlocked==0 and not is_instance_valid(fresh.match_node))
 for f in paths:DirAccess.remove_absolute(f)
 fresh.free();await process_frame
 var fails=checks.filter(func(q):return not q.passed).size()
 print(JSON.stringify({"suite":"campaign_progress_contract","scope":"Controlled authored terminal gates and real menu callbacks, ordinary surrender, retry, endpoint layout and checkpoint isolation. Controlled survival/escort wins are not natural full matches or phone proof.","checks":checks,"failed":fails}))
 quit(1 if fails else 0)
