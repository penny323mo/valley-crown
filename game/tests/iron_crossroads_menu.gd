extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
func _initialize():call_deferred("run")
func ck(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func settle():
 for i in 4:await process_frame
func click(button):
 var p=button.get_global_rect().get_center()
 for down in [true,false]:
  var e=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.position=p;e.pressed=down;root.push_input(e)
  await process_frame
 await settle()
func fit(shell,size):
 var area=Rect2(Vector2.ZERO,Vector2(size))
 return shell.buttons.get_children().all(func(b):return area.encloses(b.get_global_rect()) and b.size.y>=44)
func run():
 root.size=Vector2i(390,844)
 var shell=load("res://main_menu.tscn").instantiate();root.add_child(shell);await settle()
 shell._choose_battle("standard");await settle()
 await click(shell.buttons.get_node("ChooseLayoutButton"))
 ck("conquest selector routes ordinary pointer without starting game",shell.page=="battlefield" and not is_instance_valid(shell.match_node))
 for size in [Vector2i(320,568),Vector2i(390,844),Vector2i(640,360)]:
  root.size=size;shell._show_page("battlefield");await settle()
  ck("three distinct maps and back are reachable "+str(size),fit(shell,size) and shell.buttons.get_child_count()==4 and shell.buttons.has_node("LayoutValleyButton") and shell.buttons.has_node("LayoutWoodlandButton") and shell.buttons.has_node("LayoutIronCrossroadsButton"))
 await click(shell.buttons.get_node("LayoutIronCrossroadsButton"))
 ck("actual pointer selects crossroads and returns briefing",shell.page=="setup" and shell.selected_layout=="iron_crossroads" and shell.battlefield_preview.layout_id=="iron_crossroads" and shell.battlefield_preview.visible)
 ck("briefing discloses tradeoff without additional start resources",shell.description.text.contains("爭奪鐵礦") and shell.description.text.contains("家礦") and not is_instance_valid(shell.match_node))
 await click(shell.buttons.get_node("LaunchMatchButton"))
 var g=shell.match_node
 ck("ordinary Launch actually starts selected crossroads under standard rules",is_instance_valid(g) and g.layout_id=="iron_crossroads" and g.skirmish_mode=="standard" and g.ai_enabled)
 if is_instance_valid(g):
  g.set_process(false);g.test_mode=true
  for i in 5:g._tick(.05)
  var captured=Codec.capture_result(g)
  ck("real checkpoints carry new layout",captured.ok and captured.data.game.layout_id=="iron_crossroads")
  if captured.ok:
   var encoded=Codec.encode(captured.data,g.Rules.BUILD_ID)
   var decoded=Codec.decode(encoded.get("bytes",PackedByteArray()),g.Rules.BUILD_ID)
   ck("new layout stable under standard codec roundtrip",encoded.ok and decoded.ok and decoded.data.game.layout_id=="iron_crossroads")
   var candidate=load("res://main.tscn").instantiate();candidate.layout_id="iron_crossroads";candidate.skirmish_mode="standard";root.add_child(candidate);candidate.set_process(false);await process_frame
   ck("strict restore applies to prepared matching new layout",Restore.apply(candidate,captured.data) and Codec.capture(candidate)==captured.data)
   candidate.free()
  g._submit("surrender");g._tick(.05)
  ck("actual completed report names crossroads",g.game_over and g.last_match_report.layout_title=="赤鐵岔道")
  shell._restart_match();await settle()
  var h=shell.match_node;ck("restart preserves crossroads identity",is_instance_valid(h) and h!=g and h.layout_id=="iron_crossroads")
  shell._open_menu()
 for mode in ["control","supply","expedition","battle"]:
  shell._choose_battle("standard");shell.selected_layout="iron_crossroads";shell._choose_battle(mode);await settle()
  ck("unsupported "+mode+" keeps explicit original map",shell.selected_layout=="valley" and not shell.buttons.has_node("ChooseLayoutButton"))
 print(JSON.stringify({"suite":"iron_crossroads_menu","scope":"Native existing menu pointer, exact checkpoint restore and restart/fallback; no device claim.","checks":checks,"failed":checks.filter(func(c):return not c.passed).size()}))
 var ok=checks.all(func(c):return c.passed)
 shell.free();await process_frame;quit(0 if ok else 1)
