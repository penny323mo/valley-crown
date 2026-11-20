extends SceneTree
## Disposable native shared-file contention. No live player-save path or fixture in public runtime.
const Progress=preload("res://scripts/campaign_progress.gd")
var path=""
var checks=[]
func _initialize():call_deferred("run")
func ck(name,value):
 checks.append({"name":name,"passed":bool(value)})
 if not value:push_error(name)
func frames():
 for _i in 4:await process_frame
func new_menu():
 var menu=load("res://main_menu.tscn").instantiate()
 menu.campaign_progress_path=path
 menu.checkpoint_path=path+"-manual"
 menu.expedition_checkpoint_path=path+"-expedition"
 menu.auto_checkpoint_path=path+"-auto"
 root.add_child(menu);return menu
func press(menu,id):
 var button=menu.buttons.get_node_or_null(id)
 assert(button!=null and button.visible and not button.disabled,id)
 button.pressed.emit();await frames()
func layout_fit(menu,size,case):
 root.size=size;menu._layout();await frames()
 var matches=menu.scroll.size.y>=100.0 and not menu.scroll.get_global_rect().intersects(menu.buttons.get_global_rect())
 var seen=[]
 for b in menu.buttons.get_children():
  var hit=b.get_global_rect()
  matches=matches and hit.size.y>=54.0 and menu.card.get_global_rect().encloses(hit) and not seen.any(func(r):return r.intersects(hit))
  seen.append(hit)
 ck(case+" campaign controls and notice prose remain visible "+str(size),matches)
func run():
 path="user://campaign-contention-"+str(Time.get_ticks_usec())+".json"
 var first=Progress.save(Progress.read(path),1,false,path)
 assert(first.ok and first.completed==1)
 for key in ["manual","expedition","auto"]:
  var f=FileAccess.open(path+"-"+key,FileAccess.WRITE)
  f.store_string("existing disposable slot "+key)
 root.size=Vector2i(390,844)
 var first_menu=new_menu();var stale=new_menu()
 await frames()
 for m in [first_menu,stale]:
  await press(m,"StartMatchButton")
  await press(m,"CampaignMenuButton")
 ck("two menus read the same original committed campaign progress",first_menu.campaign_unlocked==1 and stale.campaign_unlocked==1)
 await press(stale,"RestartCampaignButton")
 ck("destructive campaign reset explicitly disclosed before launch",stale.description.text.contains("清除這個瀏覽器") and stale.buttons.get_node("LaunchMatchButton").text=="清除進度並出征" and Progress.read(path).raw==first.raw)
 # Simulate another owner tab advancing its progress with exact backend; not a played victory.
 var next=Progress.save(first_menu.campaign_storage,2,false,path)
 assert(next.ok and next.completed==2)
 await press(stale,"LaunchMatchButton")
 ck("stale reset stays on campaign page without a live replacement match",stale.menu_layer.visible and stale.page=="campaign" and not is_instance_valid(stale.match_node))
 ck("stale reset preserves exact new bytes and displays actual new unlock",stale.campaign_unlocked==2 and Progress.read(path).raw==next.raw and stale.buttons.get_node("CampaignChapterButton").text.contains("3"))
 ck("stale reset clearly discloses that it did not erase progress",stale.description.text.contains("未有清除"))
 for size in [Vector2i(568,320),Vector2i(640,360),Vector2i(390,844)]:
  await layout_fit(stale,size,"four")
 await press(stale,"ReplayCampaignButton")
 ck("non-destructive replay is an explicitly different action",stale.description.text.contains("不改動已完成紀錄") and stale.buttons.get_node("LaunchMatchButton").text=="出征")
 await press(stale,"LaunchMatchButton")
 var replay=stale.match_node
 replay.set_process(false)
 ck("non-destructive replay starts an ordinary first battle without writes",replay.campaign_chapter==0 and stale.live_campaign_replay and Progress.read(path).raw==next.raw)
 replay._submit("surrender");replay._tick(0.05)
 replay.end_actions.get_node("ReplayMatchButton").pressed.emit();await frames()
 replay=stale.match_node;replay.set_process(false)
 ck("retry preserves replay identity and shared progress",stale.live_campaign_replay and replay.campaign_chapter==0 and Progress.read(path).raw==next.raw)
 # Controlled authorized terminal branch, not a completed ordinary journey.
 replay.breach_mission.stage=2;replay._check_end()
 ck("replay victory does not change progress or promise automatic next",replay.outcome=="victory" and Progress.read(path).raw==next.raw and stale.campaign_unlocked==2 and replay.end_setup_button.text=="戰役流程")
 replay.end_setup_button.pressed.emit();await frames()
 ck("replay returns to real third-chapter unlock",stale.page=="campaign" and stale.campaign_unlocked==2 and stale.buttons.get_node("CampaignChapterButton").text.contains("3"))
 await press(stale,"RestartCampaignButton")
 await press(stale,"BackButton")
 ck("back cancels reset without write",Progress.read(path).raw==next.raw and stale.campaign_unlocked==2)
 await press(stale,"RestartCampaignButton")
 await press(stale,"LaunchMatchButton")
 var reset=Progress.read(path)
 ck("explicit current reset only starts once confirmed and read back",not stale.live_campaign_replay and stale.match_node.campaign_chapter==0 and reset.completed==0 and reset.revision==3)
 var launched=stale.match_node
 launched.set_process(false)
 launched.breach_mission.stage=2;launched._check_end()
 launched.end_setup_button.pressed.emit();await frames()
 await press(stale,"BackButton")
 await press(stale,"RestartCampaignButton")
 var corrupt=FileAccess.open(path,FileAccess.WRITE)
 corrupt.store_string("malformed disposable campaign state")
 corrupt.close()
 await press(stale,"LaunchMatchButton")
 ck("unreadable record never replaces existing finished match",stale.match_node==launched and launched.game_over and stale.menu_layer.visible and stale.page=="campaign" and stale.description.text.contains("未能清除") and not stale.buttons.has_node("RestartCampaignButton"))
 ck("unreadable record is not silently rewritten",FileAccess.get_file_as_string(path)=="malformed disposable campaign state")
 for key in ["manual","expedition","auto"]:
  ck("campaign operations preserve independent "+key+" bytes",FileAccess.get_file_as_string(path+"-"+key)=="existing disposable slot "+key)
 path=path+"-all"
 var one=Progress.save(Progress.read(path),1,false,path)
 var two=Progress.save(one,2,false,path)
 var full=new_menu();await frames()
 await press(full,"StartMatchButton");await press(full,"CampaignMenuButton")
 await press(full,"RestartCampaignButton")
 var three=Progress.save(two,3,false,path)
 assert(three.ok)
 await press(full,"LaunchMatchButton")
 ck("stale reset protects a complete 3/3 campaign and cannot start a fresh battle",full.campaign_unlocked==3 and full.description.text.contains("未有清除") and full.menu_layer.visible and not is_instance_valid(full.match_node) and Progress.read(path).raw==three.raw and not full.buttons.has_node("CampaignChapterButton"))
 for size in [Vector2i(568,320),Vector2i(640,360)]:
  await layout_fit(full,size,"three")
 full.queue_free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"campaign_contention_contract","scope":"bound native campaign menu, disposable shared scoped storage, injected contender write and replay terminal; no unrelated slots","checks":checks,"failed":failed}))
 first_menu.queue_free();stale.queue_free();quit(0 if failed==0 else 1)
