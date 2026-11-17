extends SceneTree
const Store=preload("res://scripts/checkpoint_store.gd")
const Auto=preload("res://scripts/auto_checkpoint.gd")
var checks=[]
func check(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
func settle():await process_frame;await process_frame
func run():
 root.size=Vector2i(960,640)
 var prefix="/tmp/v90-auto-"+str(Time.get_ticks_usec())
 var shell=load("res://main_menu.tscn").instantiate();shell.checkpoint_path=prefix+"-manual.bin";shell.auto_checkpoint_path=prefix+"-auto.bin";root.add_child(shell);await settle()
 shell._choose_battle("standard");shell._start_match();await settle()
 var g=shell.match_node;g.set_process(false);g.test_mode=true;g.ai_enabled=false
 for i in 25:g._tick(g.Rules.TICK)
 shell._open_menu();await settle()
 check("default off does not save on pause",not shell.auto_checkpoint_enabled and not FileAccess.file_exists(shell.auto_checkpoint_path))
 check("manual slot saves independently",Store.save_slot(g,shell.checkpoint_path).ok)
 var manual_hash=FileAccess.get_sha256(shell.checkpoint_path)
 shell._show_page("auto_checkpoint");shell.buttons.get_node("ToggleAutoCheckpointButton").pressed.emit();await settle()
 var saved=Auto.read_slot(g.Rules.BUILD_ID,shell.auto_checkpoint_path)
 check("explicit session optin saves settled paused match",saved.ok and saved.data.game.tick_count==g.tick_count and shell.auto_checkpoint_writes==1)
 check("success time and session limitation visible",shell.description.text.contains("遊戲 1 秒") and shell.description.text.contains("預設關閉") and shell.description.text.contains("強制關閉"))
 check("automatic write never replaces manual bytes",FileAccess.get_sha256(shell.checkpoint_path)==manual_hash)
 shell._schedule_auto_checkpoint(g);shell._schedule_auto_checkpoint(g);await settle()
 check("same instance tick deduplicates double pause",shell.auto_checkpoint_writes==1)
 shell._resume_match();await settle();g.set_process(false)
 for i in 21:g._tick(g.Rules.TICK)
 var expected_tick=g.tick_count
 # Product native background-notification path; no test-mode bypass.
 g.test_mode=false;g._notification(NOTIFICATION_APPLICATION_FOCUS_OUT);g._notification(NOTIFICATION_APPLICATION_PAUSED);await settle();g.test_mode=true
 check("real background pause saves once at newer tick",g.paused and shell.auto_checkpoint_writes==2 and Auto.read_slot(g.Rules.BUILD_ID,shell.auto_checkpoint_path).data.game.tick_count==expected_tick)
 var stable_hash=FileAccess.get_sha256(shell.auto_checkpoint_path)
 g.test_mode=false;g._notification(NOTIFICATION_APPLICATION_FOCUS_IN);g._notification(NOTIFICATION_APPLICATION_RESUMED);g.test_mode=true
 g._toggle_pause();g._tick(g.Rules.TICK);g._toggle_pause()
 check("new tick pause actually queues deferred save",not shell.auto_checkpoint_pending.is_empty())
 shell.auto_checkpoint_enabled=false;await settle()
 check("disabled setting blocks queued write",shell.auto_checkpoint_writes==2 and FileAccess.get_sha256(shell.auto_checkpoint_path)==stable_hash)
 var new_shell=load("res://main_menu.tscn").instantiate();new_shell.auto_checkpoint_path=shell.auto_checkpoint_path;new_shell.checkpoint_path=shell.checkpoint_path;root.add_child(new_shell);await settle()
 check("new session resets optin but offers continue",not new_shell.auto_checkpoint_enabled and new_shell.buttons.has_node("ContinueAutoCheckpointButton"))
 for size in [Vector2i(390,844),Vector2i(640,360),Vector2i(320,568)]:
  root.size=size;new_shell._show_page("home");await settle()
  var fit=true
  for button in new_shell.buttons.get_children():fit=fit and Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()) and button.size.y>=44
  check("continue home and saved summary fit "+str(size),fit and new_shell.scroll.size.y>=50 and not new_shell.footer.text.contains("不會保留"))
 root.size=Vector2i(960,640);new_shell._show_page("home");await settle()
 new_shell.buttons.get_node("ContinueAutoCheckpointButton").pressed.emit();await settle()
 var loaded=new_shell.match_node;loaded.set_process(false);loaded.test_mode=true
 check("continue restores exact saved tick paused",loaded.paused and loaded.tick_count==expected_tick and loaded.skirmish_mode=="standard")
 check("restore keeps bank and queue without offline progress",loaded.economy.bank_milli(0)==g.economy.bank_milli(0) and loaded._first(0,"town_center").queue==g._first(0,"town_center").queue)
 check("continue leaves manual slot unchanged",FileAccess.get_sha256(shell.checkpoint_path)==manual_hash)
 new_shell.auto_checkpoint_enabled=true;new_shell.auto_checkpoint_path=prefix+"-missing-dir/auto.bin";new_shell._schedule_auto_checkpoint(loaded);await settle()
 check("write failure is explicit with existing slot intact",new_shell.auto_checkpoint_status.contains("失敗") and new_shell.auto_checkpoint_writes==0 and FileAccess.get_sha256(shell.auto_checkpoint_path)==stable_hash)
 new_shell.auto_checkpoint_path=new_shell.checkpoint_path;new_shell.auto_checkpoint_last_attempt="";new_shell._schedule_auto_checkpoint(loaded);await settle()
 check("misconfigured auto path cannot overwrite manual slot",new_shell.auto_checkpoint_status.contains("SLOT_CONFLICT") and FileAccess.get_sha256(new_shell.checkpoint_path)==manual_hash)
 new_shell.auto_checkpoint_path=new_shell.expedition_checkpoint_path;new_shell.auto_checkpoint_last_attempt="";new_shell._schedule_auto_checkpoint(loaded);await settle()
 check("expedition manual slot alias is also rejected",new_shell.auto_checkpoint_status.contains("SLOT_CONFLICT"))
 var old=loaded
 new_shell.auto_checkpoint_path=prefix+"-corrupt.bin";var f=FileAccess.open(new_shell.auto_checkpoint_path,FileAccess.WRITE);f.store_string("invalid");f.close()
 new_shell._load_auto_checkpoint();await settle()
 check("invalid restore leaves live match untouched",new_shell.match_node==old and old.tick_count==expected_tick)
 for mode in ["escort","expedition"]:
  var prior=loaded.skirmish_mode;loaded.skirmish_mode=mode
  check("unsupported mode refused "+mode,not Auto.save_slot(loaded,prefix+mode).ok and not FileAccess.file_exists(prefix+mode));loaded.skirmish_mode=prior
 new_shell.auto_checkpoint_path=shell.auto_checkpoint_path;new_shell.auto_checkpoint_last_attempt=""
 var old_id=loaded.get_instance_id();new_shell._schedule_auto_checkpoint(loaded);var stale_key=new_shell.auto_checkpoint_pending
 new_shell._restart_match();await settle()
 var replacement=new_shell.match_node;replacement.set_process(false);replacement.test_mode=true;replacement.ai_enabled=false
 new_shell._write_auto_checkpoint(old_id,stale_key)
 check("queued and stale previous match callbacks cannot overwrite slot",replacement!=old and new_shell.auto_checkpoint_writes==0 and FileAccess.get_sha256(shell.auto_checkpoint_path)==stable_hash)
 new_shell._open_menu();await settle()
 for size in [Vector2i(390,844),Vector2i(640,360),Vector2i(320,568)]:
  root.size=size;new_shell._show_page("auto_checkpoint");await settle()
  var fit=true
  for button in new_shell.buttons.get_children():fit=fit and Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()) and button.size.y>=44
  check("auto settings controls fit "+str(size),fit and new_shell.scroll.size.y>=50)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"auto_checkpoint_contract","checks":checks,"failed":failed,"scope":"Native ordinary match pause/background notifications and isolated local files. Not browser IndexedDB durability, forced-kill guarantee, physical mobile or cross-build migration."}))
 quit(1 if failed else 0)
