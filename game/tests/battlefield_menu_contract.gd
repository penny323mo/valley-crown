extends SceneTree
var checks=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred("run")
func run():
 var shell=load("res://main_menu.tscn").instantiate();root.add_child(shell);await process_frame
 shell.history_path="/tmp/map-menu-history-"+str(Time.get_ticks_usec())+".json"
 shell._choose_battle("standard")
 check("ordinary briefing exposes battlefield selector",shell.buttons.has_node("ChooseLayoutButton"))
 shell.buttons.get_node("ChooseLayoutButton").pressed.emit()
 check("map selector does not launch battle",shell.page=="battlefield" and not is_instance_valid(shell.match_node))
 shell.buttons.get_node("LayoutWoodlandButton").pressed.emit()
 check("woodland selection returns exact briefing",shell.selected_layout=="woodland" and shell.page=="setup" and shell.description.text.contains("雙翼林地"))
 check("briefing public diagram is not live battlefield",shell.battlefield_preview.visible and shell.battlefield_preview.layout_id=="woodland" and not is_instance_valid(shell.match_node))
 for size in [Vector2i(320,568),Vector2i(640,360),Vector2i(390,844)]:
  root.size=size;shell._show_page("setup");await process_frame;await process_frame
  var fit=true
  for button in shell.buttons.get_children():fit=fit and Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()) and button.size.y>=44
  check("map briefing actions remain reachable "+str(size),fit)
 shell._replace_match();var g=shell.match_node;g.set_process(false);g.test_mode=true;g.history_path=shell.history_path
 check("launch installs woodland before ready",g.layout_id=="woodland" and g.skirmish_mode=="standard")
 g._submit("surrender");g._tick(.05)
 check("terminal report names actual battlefield",g.game_over and g.last_match_report.layout_title=="雙翼林地" and g.MatchReport.page_text(g.last_match_report,"overview").contains("雙翼林地"))
 shell._restart_match();await process_frame;await process_frame
 g=shell.match_node;g.set_process(false);g.test_mode=true;g.history_path=shell.history_path
 check("replay retains same battlefield",g.layout_id=="woodland")
 shell._open_menu();shell._choose_battle("expedition")
 check("fixed scripted mission explicitly uses classic",shell.selected_layout=="valley" and not shell.buttons.has_node("ChooseLayoutButton") and shell.description.text.contains("經典谷地"))
 shell._choose_battle("control")
 check("control mode cannot silently retain woodland",shell.selected_layout=="valley" and not shell.buttons.has_node("ChooseLayoutButton"))
 shell._choose_battle("standard");shell._show_page("battlefield");shell.buttons.get_node("LayoutBackButton").pressed.emit()
 check("cancel map selector preserves paused current battle",shell.match_node==g and shell.page=="setup" and g.paused)
 shell.queue_free();await process_frame
 var failed=checks.filter(func(c):return not c.passed).size();print(JSON.stringify({"suite":"battlefield_menu_contract","checks":checks,"failed":failed}));quit(1 if failed else 0)
