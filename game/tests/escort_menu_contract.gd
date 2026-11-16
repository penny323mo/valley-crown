extends SceneTree
const Policy=preload("res://scripts/skirmish_policy.gd")
const Layout=preload("res://scripts/battlefield_layout.gd")
const Catalogue=preload("res://scripts/battle_selection.gd")
class MatchStub:
 extends Node
 var skirmish_mode="escort"
 var game_over=false
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 check("escort is explicitly supported policy",Policy.valid("escort")=="escort" and Policy.title("escort")=="護送拓荒隊")
 var entry=Catalogue.option("escort")
 check("escort is selectable scripted conquest",entry.get("group",-1)==3 and entry.get("mode","")=="escort" and entry.get("victory","")=="conquest")
 check("catalogue retains nine earlier configurations",Catalogue.OPTIONS.size()==10 and ["practice","standard","pressure","control","supply","battle","fortress","survival","expedition"].all(func(id):return not Catalogue.option(id).is_empty()))
 var brief=Catalogue.briefing("escort","conquest")
 check("briefing discloses no save and no economic AI",brief.contains("暫不支援存檔") and brief.contains("沒有經濟 AI") and brief.contains("不消耗敵方資源"))
 check("briefing explains paid forward construction and defeat",brief.contains("正常付費") and brief.contains("三名任務村民全部死亡") and brief.contains("建築被毀可重建"))
 var shell=load("res://main_menu.tscn").instantiate()
 var prefix="/tmp/escort-menu-"+str(Time.get_ticks_usec())
 shell.checkpoint_path=prefix+"-ordinary.bin";shell.expedition_checkpoint_path=prefix+"-expedition.bin";shell.history_path=prefix+"-history.json"
 root.add_child(shell);await process_frame
 for size in [Vector2i(390,844),Vector2i(640,360)]:
  root.size=size;shell.battle_group=3;shell._show_page("battle_options");await process_frame;await process_frame
  var button=shell.buttons.get_node("ChooseBattle_escort")
  check(str(size)+" escort entry fits touch viewport",Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()) and button.size.y>=44)
  button.pressed.emit();await process_frame;await process_frame
  check(str(size)+" selection opens escort briefing without battlefield",shell.page=="setup" and shell.selected_mode=="escort" and not is_instance_valid(shell.match_node))
  check(str(size)+" briefing retains scroll and launch",shell.description.text=="戰場："+Layout.title("valley")+"\n"+Layout.details("valley")+"\n\n"+brief and is_instance_valid(shell.buttons.get_node("LaunchMatchButton")) and shell.scroll.size.y>0)
 var stub=MatchStub.new();shell.add_child(stub);shell.match_node=stub
 shell._show_page("checkpoint");await process_frame
 check("escort checkpoint page discloses unsupported",shell.description.text.contains("護送拓荒隊暫不支援存檔"))
 check("escort checkpoint page offers no save",not shell.buttons.has_node("SaveCheckpointButton"))
 stub.skirmish_mode="standard";shell._show_page("checkpoint")
 check("ordinary save action preserved",shell.buttons.has_node("SaveCheckpointButton"))
 stub.skirmish_mode="expedition";shell._show_page("checkpoint")
 check("expedition save action preserved",shell.buttons.has_node("SaveCheckpointButton"))
 check("selection and checkpoint menus write neither slot",not FileAccess.file_exists(shell.checkpoint_path) and not FileAccess.file_exists(shell.expedition_checkpoint_path))
 shell.match_node=null;stub.free()
 shell.selected_mode="escort";shell.selected_victory_mode="conquest"
 shell._replace_match();await process_frame
 var actual=shell.match_node;actual.set_process(false);actual.test_mode=true;actual.history_path=prefix+"-match-history.json"
 check("escort launch preserves selected mode and normal opening",actual.skirmish_mode=="escort" and actual.victory_mode=="conquest" and actual.tick_count<=1 and not actual.game_over)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"escort_menu_contract","checks":checks,"failed":failed}))
 shell.free();quit(0 if failed==0 else 1)
