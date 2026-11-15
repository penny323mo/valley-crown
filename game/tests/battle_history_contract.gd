extends SceneTree
const History=preload("res://scripts/battle_history.gd")
const Report=preload("res://scripts/match_report.gd")
const PATH="user://history_contract_only.json"
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 if FileAccess.file_exists(PATH):DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
 check("absent history starts empty",History.read_history(PATH)=={"ok":true,"entries":[]})
 var report=Report.new().make_report("victory","keep_destroyed",1200,-1,{"delivered":{},"purchased":{},"repaired":{},"refunded":{}},{})
 check("finished report saves locally",History.append_report(report,"match-0",PATH).ok)
 var saved=History.read_history(PATH)
 check("reopen recovers report without world state",saved.ok and saved.entries.size()==1 and saved.entries[0].pages.size()==4 and saved.entries[0].pages.overview.contains("01:00"))
 check("duplicate save does not add second match",History.append_report(report,"match-0",PATH).get("duplicate",false) and History.read_history(PATH).entries.size()==1)
 for i in range(1,13):History.append_report(report,"match-"+str(i),PATH)
 saved=History.read_history(PATH)
 check("ten newest completed matches retained",saved.entries.size()==10 and saved.entries[0].id=="match-12" and saved.entries[-1].id=="match-3")
 var text=FileAccess.get_file_as_string(PATH)
 check("unfinished report rejected without replacing file",not History.append_report({"outcome":"playing"},"bad",PATH).ok and FileAccess.get_file_as_string(PATH)==text)
 var shell=load("res://main_menu.tscn").instantiate();shell.history_path=PATH;root.add_child(shell);await process_frame
 shell._show_page("help");shell.buttons.get_node("BattleHistoryButton").pressed.emit()
 check("menu opens archived victory without starting game",shell.page=="history" and shell.heading.text.contains("勝利") and not is_instance_valid(shell.match_node))
 check("storage limits and no resume clearly disclosed",shell.description.text.contains("最近十場") and shell.description.text.contains("未完成戰役不能讀檔續玩") and shell.description.text.contains("清除網站資料"))
 shell.buttons.get_node("HistoryPageButton").pressed.emit()
 check("economy page reads saved report",shell.description.text.contains("資源帳目"))
 shell.buttons.get_node("HistoryNextButton").pressed.emit()
 check("older match changes index and resets page",shell.history_index==1 and shell.history_page==0)
 for size in [Vector2i(320,568),Vector2i(390,844),Vector2i(844,390)]:
  root.size=size;shell._layout();await process_frame;await process_frame
  for button in shell.buttons.get_children():check("history button fits %s %s" % [size,button.name],Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()))
 var file=FileAccess.open(PATH,FileAccess.WRITE);file.store_string("broken json");file.close()
 check("corrupted history gives recoverable error",not History.read_history(PATH).ok)
 check("corrupted file never silently overwritten",not History.append_report(report,"fresh",PATH).ok and FileAccess.get_file_as_string(PATH)=="broken json")
 shell._show_page("history");check("menu shows read failure without crash",shell.description.text.contains("損壞") and shell.buttons.get_child_count()==1)
 file=FileAccess.open(PATH,FileAccess.WRITE);file.store_string(JSON.stringify({"version":999,"entries":[]}));file.close()
 check("unknown schema preserved",not History.read_history(PATH).ok and not History.append_report(report,"fresh",PATH).ok)
 DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
 shell.queue_free();await process_frame
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.ai_enabled=false;g.test_mode=true;g._test_reset();g.set_process(false);g.history_path=PATH
 g._kill(g._first(1,"town_center"));g._check_end()
 check("diagnostic matches do not write player history",not FileAccess.file_exists(PATH))
 g._test_reset();g.set_process(false);g.test_mode=false;g._kill(g._first(1,"town_center"));g._check_end()
 check("actual end lifecycle records one victory",History.read_history(PATH).entries.size()==1 and History.read_history(PATH).entries[0].outcome=="victory")
 g._check_end();check("repeated end update does not duplicate",History.read_history(PATH).entries.size()==1)
 g.queue_free();DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"battle_history_contract","checks":checks,"failed":failed,"scope":"native local file roundtrip, controlled terminal fixture and menu layout; not browser restart persistence or physical phone acceptance"}));quit(1 if failed else 0)
