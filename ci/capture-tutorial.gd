extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var menu
var g
var out=""
var metadata_only=false
var checks=[]
var report={"captures":[],"actions":[],"scope":"Real product signals, ordinary seeded practice and queued gather with actual ticks. No free resources, health, spawns, tutorial facts or fog changes. No physical phone/browser validation. Native inspection required."}
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
 var row={"name":name,"page":menu.page,"description":menu.description.text,"scroll":menu.scroll.scroll_vertical,"metadata_only":metadata_only}
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
func run():
 var args=OS.get_cmdline_user_args();out=args[0] if args.size()>0 else "/tmp/v89-capture"
 if DirAccess.dir_exists_absolute(out):quit(2);return
 DirAccess.make_dir_recursive_absolute(out);metadata_only=DisplayServer.get_name()=="headless" or "--metadata-only" in args
 report.build=Rules.BUILD_ID;report.driver_sha256=FileAccess.get_sha256(get_script().resource_path)
 for p in ["main_menu","game","demo_tutorial","rules"]:report[p+"_sha256"]=FileAccess.get_sha256("res://scripts/"+p+".gd")
 root.size=Vector2i(960,540);menu=load("res://main_menu.tscn").instantiate();root.add_child(menu);await process_frame;await process_frame
 if not await press("HelpButton"):finish();return
 await shot("01-guided-entry")
 if not await press("GuidedPracticeButton"):finish();return
 menu.scroll.scroll_vertical=int(menu.scroll.get_v_scroll_bar().max_value);await process_frame
 await shot("02-practice-setup")
 if not await press("LaunchMatchButton"):finish();return
 g=menu.match_node;g.set_process(false)
 check("normal practice five villagers",g.skirmish_mode=="practice" and g._count(0,"villager")==5)
 expire_toast()
 g.guidance_detail_button.pressed.emit();await process_frame
 await shot("03-initial-checklist")
 var worker=g._first(0,"villager");g._select([worker.id]);expire_toast()
 var target=g.demo_tutorial.locate(g.faction_views[0].records())
 check("normal visible gather target",target.ok)
 if not target.ok:finish();return
 var bank=g.economy.bank_milli(0).duplicate(true)
 g._submit("order",{"ids":[worker.id],"target":target.id,"position":target.position},0)
 for i in 1000:
  g._tick(Rules.TICK)
  if g.demo_tutorial.achieved.has("deposit"):break
 expire_toast()
 check("three real steps",g.demo_tutorial.achieved.has("select") and g.demo_tutorial.achieved.has("gather") and g.demo_tutorial.achieved.has("deposit"))
 check("gather actually delivered",g.economy.bank_milli(0).food>bank.food or g.economy.bank_milli(0).wood>bank.wood)
 if g.context_detail_kind!="guidance":g.guidance_detail_button.pressed.emit()
 await shot("04-delivered-checklist")
 var selection=g.selected.duplicate();var orders=g.commands.duplicate(true);var stock=g.economy.bank_milli(0).duplicate(true)
 var location=g.demo_tutorial.locate(g.faction_views[0].records())
 g.tutorial_locate.pressed.emit();await process_frame
 check("locate camera only",location.ok and g.camera_focus==location.position and g.selected==selection and g.commands==orders and g.economy.bank_milli(0)==stock)
 expire_toast();await shot("05-located-building")
 # Close details so ordinary tutorial skip is actually visible.
 var close=g.find_child("CloseBattleDetails",true,false)
 close.pressed.emit();await process_frame;g._refresh_tutorial()
 check("skip control visible",g.tutorial_skip.is_visible_in_tree());g.tutorial_skip.pressed.emit()
 var facts=g.demo_tutorial.achieved.duplicate()
 await open_home()
 if not await press("HelpButton"):finish();return
 await shot("06-resume-entry")
 if not await press("ResumeTutorialButton"):finish();return
 check("resume preserves match facts",menu.match_node==g and not g.demo_tutorial.skipped and g.demo_tutorial.achieved==facts)
 if not await press("BackButton"):finish();return
 if not await press("ResumeMatchButton"):finish();return
 g.set_process(false);expire_toast()
 if g.context_detail_kind!="guidance":g.guidance_detail_button.pressed.emit()
 await shot("07-resumed-progress")
 finish()
