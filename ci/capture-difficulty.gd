extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var menu
var out=""
var metadata_only=false
var checks=[]
var report={"scope":"Actual product main-menu signals and layout; normal-start lower-raid-pressure game. No artwork substitution, stocks/health/units/fog overrides, simulation fast-forward or fabricated screenshot. Native captures do NOT validate physical phone/browser or actual 180-second raid behavior.","captures":[],"actions":[]}
func _initialize():call_deferred("run")
func check(n,b,d=null):checks.append({"name":n,"pass":bool(b),"detail":d});return bool(b)
func press(id):
 var b=menu.find_child(id,true,false)
 if not check("product control available: "+id,b is Button and b.is_visible_in_tree()):return false
 report.actions.append({"signal":"pressed","button":id,"text":b.text,"page_before":menu.page})
 b.pressed.emit();await process_frame;await process_frame
 return true
func button_info():
 var rows=[];var viewport=Rect2(Vector2.ZERO,Vector2(root.size))
 for b in menu.buttons.get_children():
  rows.append({"id":b.name,"text":b.text,"rect":str(b.get_global_rect()),"inside_viewport":viewport.encloses(b.get_global_rect()),"visible":b.is_visible_in_tree()})
 return rows
func capture(name,required=[]):
 await process_frame
 var rows=button_info()
 for id in required:
  var found=false
  for b in rows:
   if b.id==id:found=b.visible and b.inside_viewport
  check(name+" usable visible button "+id,found)
 var row={"name":name,"viewport":str(root.size),"page":menu.page,"difficulty":menu.selected_difficulty,"heading":menu.heading.text,"description":menu.description.text,"description_rect":str(menu.description.get_global_rect()),"scroll_rect":str(menu.scroll.get_global_rect()),"scroll_value":menu.scroll.scroll_vertical,"scroll_max":menu.scroll.get_v_scroll_bar().max_value,"scroll_page":menu.scroll.get_v_scroll_bar().page,"buttons":rows,"metadata_only":metadata_only}
 if is_instance_valid(menu.match_node):
  var g=menu.match_node;g._camera_update();g._refresh_fog();g._update_visuals(0.0);g._update_hud()
  row.game={"ai_difficulty":g.ai_difficulty,"ai_enabled":g.ai_enabled,"snapshot":g._snapshot(),"pause_text":g.pause_button.text}
 if not metadata_only:
  await RenderingServer.frame_post_draw
  var path=out+"/"+name+".png";var error=root.get_texture().get_image().save_png(path)
  check(name+" native PNG saved",error==OK);row.file=path;row.sha256=FileAccess.get_sha256(path)
 report.captures.append(row)
func finish():
 report.checks=checks;report.failed=checks.filter(func(x):return not x.pass).size();report.status="PASS_METADATA_ONLY" if metadata_only else "CAPTURED_NATIVE_PRODUCT_UI"
 if report.failed:report.status="FAILED_INCOMPLETE"
 var f=FileAccess.open(out+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close();print(JSON.stringify({"status":report.status,"failed":report.failed,"build":report.build}));quit(0 if report.failed==0 else 1)
func run():
 var args=OS.get_cmdline_user_args();out=args[0] if args.size()>0 else "/tmp/v88-difficulty-capture"
 if DirAccess.dir_exists_absolute(out):push_error("Refusing to overwrite evidence");quit(2);return
 DirAccess.make_dir_recursive_absolute(out)
 metadata_only="--metadata-only" in args or DisplayServer.get_name()=="headless"
 report.build=Rules.BUILD_ID;report.physical_phone_validated=false;report.renderer=DisplayServer.get_name();report.driver_sha256=FileAccess.get_sha256(get_script().resource_path)
 for path in ["res://scripts/rules.gd","res://scripts/main_menu.gd","res://scripts/ai_difficulty.gd","res://scripts/battle_selection.gd","res://scripts/game.gd"]:report[path]=FileAccess.get_sha256(path)
 root.size=Vector2i(960,540);menu=load("res://main_menu.tscn").instantiate();root.add_child(menu);await process_frame;await process_frame
 for id in ["StartMatchButton","BattleGroup0","ChooseBattle_standard"]:
  if not await press(id):finish();return
 check("standard difficulty default",menu.selected_difficulty=="standard")
 await capture("01-standard-setup",["ChooseDifficultyButton","LaunchMatchButton"])
 if not await press("ChooseDifficultyButton"):finish();return
 await capture("02-pressure-choice",["DifficultyEasyButton","DifficultyStandardButton"])
 if not await press("DifficultyEasyButton"):finish();return
 check("lower pressure selected through product signal",menu.selected_difficulty=="easy")
 check("easy setup describes180seconds and5soldier cap",menu.description.text.contains("180") and menu.description.text.contains("5"))
 await capture("03-lower-pressure-setup",["ChooseDifficultyButton","LaunchMatchButton"])
 # Existing product prose scroll; preserve buttons while showing the full brief.
 menu.scroll.scroll_vertical=int(menu.scroll.get_v_scroll_bar().max_value);await process_frame
 await capture("04-lower-pressure-details",["ChooseDifficultyButton","LaunchMatchButton"])
 root.size=Vector2i(390,844);await process_frame;await process_frame;menu.scroll.scroll_vertical=0;await process_frame
 await capture("05-narrow-setup",["ChooseDifficultyButton","LaunchMatchButton"])
 menu.scroll.scroll_vertical=int(menu.scroll.get_v_scroll_bar().max_value);await process_frame
 await capture("06-narrow-details",["ChooseDifficultyButton","LaunchMatchButton"])
 root.size=Vector2i(960,540);await process_frame;await process_frame
 if not await press("LaunchMatchButton"):finish();return
 check("normal game receives easy selection",is_instance_valid(menu.match_node) and menu.match_node.ai_difficulty=="easy")
 if is_instance_valid(menu.match_node):
  var g=menu.match_node;g.set_process(false)
  check("normal initial population6",g._population(0)==6)
  g.pause_button.pressed.emit();await process_frame
  check("product pause signal pauses match",g.paused)
  report.pause_scope="Actual paused normal-start game; difficulty metadata is not proof of any on-screen difficulty label. No raid timing test performed."
  await capture("07-easy-paused-game")
  g.compact_menu_button.pressed.emit();await process_frame
  g.shortcut_category_buttons.settings.pressed.emit();await process_frame
  var home_button=null
  for control in g.compact_menu.find_children("*","Button",true,false):
   if control.text=="主選單":home_button=control;break
  if not check("actual game main menu button present",home_button!=null and home_button.is_visible_in_tree()):finish();return
  report.actions.append({"signal":"pressed","button":"game shortcut settings > 主選單","text":home_button.text})
  home_button.pressed.emit();await process_frame;await process_frame
  check("actual game main menu route",menu.page=="home" and g.paused)
  check("home description contains actual match difficulty",menu.description.text.contains("本局電腦：較低襲擊壓力"))
  report.pause_scope="Actual game menu return to paused home with match difficulty label. Product hides match and HUD here; game background is NOT forcibly shown. Previous capture preserves actual paused battlefield. No raid timing test."
  menu.scroll.scroll_vertical=int(menu.scroll.get_v_scroll_bar().max_value)
  await process_frame;await process_frame
  var clip=menu.scroll.get_global_rect()
  var desc=menu.description.get_global_rect()
  var line_height=menu.description.get_line_height()
  var last_line=Rect2(Vector2(desc.position.x,desc.end.y-line_height),Vector2(desc.size.x,line_height))
  check("home final difficulty line lies inside scroll clip",clip.encloses(last_line))
  report.home_difficulty_visibility={"description_rect":str(desc),"last_line_rect":str(last_line),"scroll_clip":str(clip),"scroll_value":menu.scroll.scroll_vertical,"scope":"Geometry of final line after normal scroll; native inspection still required"}
  await capture("08-easy-match-home",["ResumeMatchButton"])
  report.captures[-1].game_visible=g.visible
  report.captures[-1].game_ui_visible=g.ui.visible
 finish()
