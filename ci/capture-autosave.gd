extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var menu
var g
var out=""
var metadata_only=false
var checks=[]
var report={"captures":[],"actions":[],"scope":"Actual product opt-in and normal pause save, ordinary queued gathering, isolated local save files. New shell is application-session recreation, NOT forced-kill or browser durability evidence. No physical phone acceptance."}
func _initialize():call_deferred("run")
func check(n,b):checks.append({"name":n,"pass":bool(b)});return bool(b)
func press(id):
 var b=menu.find_child(id,true,false)
 if not check("button "+id,b is Button and b.is_visible_in_tree()):return false
 report.actions.append(id);b.pressed.emit();await process_frame;await process_frame;return true
func expire_toast():
 # Run actual product presentation/time handling, not direct toast reset.
 for i in 120:
  if g.toast_time<=0:break
  g._process(0.1)
 g._refresh_tutorial();g._update_hud()
func shot(name):
 if is_instance_valid(g):
  g._camera_update();g._refresh_fog();g._update_visuals(0.0);g._update_hud();g._refresh_tutorial()
 await process_frame;await process_frame
 var row={"name":name,"page":menu.page,"description":menu.description.text,"description_rect":str(menu.description.get_global_rect()),"scroll_rect":str(menu.scroll.get_global_rect()),"autosave_status":menu.auto_checkpoint_status,"scroll":menu.scroll.scroll_vertical,"metadata_only":metadata_only}
 if is_instance_valid(g):row.game={"tick":g.tick_count,"mode":g.skirmish_mode,"bank":g.economy.bank_milli(0),"achieved":g.demo_tutorial.achieved.duplicate(),"skipped":g.demo_tutorial.skipped,"checklist":g.guidance_detail.text,"camera":str(g.camera_focus),"selected":g.selected.duplicate(),"toast_time":g.toast_time,"locate_visible":g.tutorial_locate.is_visible_in_tree(),"details_rect":str(g.context_details.get_global_rect())}
 if not metadata_only:
  await RenderingServer.frame_post_draw
  var path=out+"/"+name+".png";check("PNG "+name,root.get_texture().get_image().save_png(path)==OK);row.sha256=FileAccess.get_sha256(path);row.file=path
 report.captures.append(row)
func open_home():
 g.compact_menu_button.pressed.emit();await process_frame
 g.shortcut_category_buttons.settings.pressed.emit();await process_frame
 for b in g.compact_menu.find_children("*","Button",true,false):
  if b.text=="主選單":b.pressed.emit();break
 await process_frame;await process_frame
func finish():
 report.checks=checks;report.failed=checks.filter(func(x):return not x.pass).size()
 var f=FileAccess.open(out+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close();print(JSON.stringify({"failed":report.failed,"checks":checks.size()}));quit(1 if report.failed else 0)
func state():
 return {"tick":g.tick_count,"bank":g.economy.bank_milli(0).duplicate(true),"entities":g._snapshot(),"paused":g.paused}
func run():
 var args=OS.get_cmdline_user_args();out=args[0] if args.size()>0 else "/tmp/v90-autosave-capture"
 if DirAccess.dir_exists_absolute(out):quit(2);return
 DirAccess.make_dir_recursive_absolute(out);metadata_only=DisplayServer.get_name()=="headless" or "--metadata-only" in args
 report.build=Rules.BUILD_ID;report.driver_sha256=FileAccess.get_sha256(get_script().resource_path)
 for p in ["main_menu","game","auto_checkpoint","rules"]:report[p+"_sha256"]=FileAccess.get_sha256("res://scripts/"+p+".gd")
 root.size=Vector2i(960,540);menu=load("res://main_menu.tscn").instantiate()
 menu.checkpoint_path=out+"/manual.bin";menu.auto_checkpoint_path=out+"/auto.bin";root.add_child(menu);await process_frame;await process_frame
 if not await press("HelpButton"):finish();return
 if not await press("GuidedPracticeButton"):finish();return
 if not await press("LaunchMatchButton"):finish();return
 g=menu.match_node;g.set_process(false)
 check("ordinary practice opening",g.skirmish_mode=="practice" and g._count(0,"villager")==5)
 await open_home()
 if not await press("CheckpointMenuButton"):finish();return
 if not await press("SaveCheckpointButton"):finish();return
 check("manual product save exists",FileAccess.file_exists(menu.checkpoint_path))
 var manual_hash=FileAccess.get_sha256(menu.checkpoint_path)
 if not await press("AutoCheckpointSettingsButton"):finish();return
 check("default session optout",not menu.auto_checkpoint_enabled and not FileAccess.file_exists(menu.auto_checkpoint_path))
 await shot("01-explicit-opt-in")
 if not await press("ToggleAutoCheckpointButton"):finish();return
 await process_frame;await process_frame
 check("optin saves paused game",menu.auto_checkpoint_enabled and FileAccess.file_exists(menu.auto_checkpoint_path))
 menu.scroll.scroll_vertical=int(menu.scroll.get_v_scroll_bar().max_value);await process_frame
 await shot("02-opted-in-save-status")
 if not await press("AutoCheckpointBackButton"):finish();return
 if not await press("CheckpointBackButton"):finish();return
 if not await press("ResumeMatchButton"):finish();return
 g.set_process(false)
 var worker=g._first(0,"villager");g._select([worker.id]);var target=g.demo_tutorial.locate(g.faction_views[0].records())
 check("visible gather target",target.ok)
 if not target.ok:finish();return
 var bank=g.economy.bank_milli(0).duplicate(true)
 g._submit("order",{"ids":[worker.id],"target":target.id,"position":target.position},0)
 for i in 1000:
  g._tick(Rules.TICK)
  if g.demo_tutorial.achieved.has("deposit"):break
 expire_toast()
 check("ordinary gathering delivered",g.economy.bank_milli(0).wood>bank.wood or g.economy.bank_milli(0).food>bank.food)
 await shot("03-real-gathered-progress")
 g.pause_button.pressed.emit();await process_frame;await process_frame
 var saved_state=state();report.saved_state=saved_state
 check("normal pause autosaved",g.paused and menu.auto_checkpoint_writes>=2)
 await shot("04-normal-pause-saved")
 await open_home()
 if not await press("CheckpointMenuButton"):finish();return
 if not await press("AutoCheckpointSettingsButton"):finish();return
 menu.scroll.scroll_vertical=int(menu.scroll.get_v_scroll_bar().max_value);await process_frame
 await shot("05-latest-save-status")
 var old=menu;root.remove_child(old);old.queue_free();await process_frame
 menu=load("res://main_menu.tscn").instantiate();menu.checkpoint_path=out+"/manual.bin";menu.auto_checkpoint_path=out+"/auto.bin";root.add_child(menu);g=null;await process_frame;await process_frame
 check("new session optout retains continue",not menu.auto_checkpoint_enabled and menu.buttons.has_node("ContinueAutoCheckpointButton"))
 menu.scroll.scroll_vertical=int(menu.scroll.get_v_scroll_bar().max_value);await process_frame
 await shot("06-new-session-continue")
 if not await press("ContinueAutoCheckpointButton"):finish();return
 g=menu.match_node;g.set_process(false)
 var restored=state();report.restored_state=restored
 check("restored paused exact tick",g.paused and restored.tick==saved_state.tick)
 check("restored exact bank",restored.bank==saved_state.bank)
 check("restored exact snapshot",restored.entities==saved_state.entities)
 check("manual slot unchanged",FileAccess.get_sha256(menu.checkpoint_path)==manual_hash)
 report.manual_sha256_before=manual_hash;report.manual_sha256_after=FileAccess.get_sha256(menu.checkpoint_path)
 await shot("07-restored-same-progress")
 finish()
