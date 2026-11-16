extends SceneTree
const Store=preload("res://scripts/checkpoint_store.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var shell=load("res://scripts/main_menu.gd").new();shell.checkpoint_path="user://checkpoint_menu_contract.bin";root.add_child(shell);await process_frame
 shell.selected_mode="survival";shell._replace_match();var g=shell.match_node;g.set_process(false);g.test_mode=true
 for i in 100:g._tick(.05)
 shell._open_menu()
 check("menu pauses before save",g.paused and g.tick_count==100)
 shell._show_page("checkpoint")
 check("local slot menu exposes save action",shell.buttons.find_child("SaveCheckpointButton",true,false)!=null)
 shell._save_checkpoint()
 var loaded=Store.read_slot(g.Rules.BUILD_ID,shell.checkpoint_path)
 check("actual local file decodes exact saved clock",loaded.ok and loaded.data.game.tick_count==100)
 var saved=Codec.capture(g)
 shell._restore_checkpoint()
 var restored=shell.match_node;restored.set_process(false)
 check("valid load replaces rather than mutates old game",restored!=g)
 check("loaded game remains paused with no offline ticks",restored.paused and restored.tick_count==100)
 check("loaded authoritative snapshot matches saved data",Codec.capture(restored)==saved)
 var current=restored
 var f=FileAccess.open(shell.checkpoint_path,FileAccess.WRITE);f.store_buffer(PackedByteArray([1,2,3]));f.close()
 shell._restore_checkpoint()
 check("corrupt slot leaves current game unchanged",shell.match_node==current and current.tick_count==100)
 check("load failure stays in explanatory menu",shell.description.text.contains("無法讀取"))
 var unopened=load("res://main.tscn").instantiate()
 check("unpaused game cannot overwrite checkpoint",not Store.save_slot(unopened,"user://unused_checkpoint.bin").ok)
 unopened.free()
 for size in [Vector2i(390,844),Vector2i(640,360),Vector2i(320,568)]:
  root.size=size;shell._show_page("checkpoint");await process_frame;await process_frame
  var fit=true
  for button in shell.buttons.get_children():fit=fit and Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()) and button.size.y>=44
  check("checkpoint touch buttons fit "+str(size),fit)
 shell.queue_free();await process_frame
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"checkpoint_menu_contract","checks":checks,"failed":failed,"scope":"Actual native local-file and menu roundtrip, not browser reload durability"}));quit(0 if failed==0 else 1)
