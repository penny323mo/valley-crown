extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
var g
var rows=[]
var checks=[]
func _initialize():call_deferred("run")
func ck(label,passed):
 checks.append({"name":label,"passed":bool(passed)})
 if not passed:push_error(label)
func run():
 var a=OS.get_cmdline_user_args()
 var out=a[0]
 var expected=a[3]
 root.size=Vector2i(int(a[1]),int(a[2]))
 if DirAccess.dir_exists_absolute(out):quit(2);return
 if DirAccess.make_dir_recursive_absolute(out)!=OK:quit(3);return
 g=load("res://main.tscn").instantiate();g.skirmish_mode="battle";g.victory_mode="conquest";g.history_path=out+"/private-history.json"
 root.add_child(g);g.set_process(false)
 for i in 200:g._process(g.Rules.TICK)
 var s=g._first(0,"spearman");var b=g._first(0,"archer")
 ck("exact shared Battle scenario mixed army",s.id==103 and b.id==105)
 g._select([s.id,b.id])
 g._camera_update();g._refresh_fog();g._update_visuals(0)
 g._update_hud();g._layout_ui()
 for i in 5:await process_frame
 ck("exact build identity",g.Rules.BUILD_ID==expected)
 ck("exact portrait viewport",root.size==Vector2i(390,844))
 ck("same tick and selection",g.tick_count==200 and g.selected==[s.id,b.id])
 ck("same neutral mode and no orders",not g.touch_command and g.commands.is_empty())
 ck("ledger conserved",g.economy.audit().ok)
 var strip=g.action_scroll.get_global_rect()
 var row={"tick":g.tick_count,"viewport":str(root.size),"bank":g.economy.bank_milli(0),"ids":g.selected.duplicate(),"at_start":g.action_scroll.scroll_horizontal==0,"buttons":[]}
 ck("no horizontal scroll",row.at_start)
 for button in g.actions.get_children():
  if button is Button and button.is_visible_in_tree():
   var rect=button.get_global_rect()
   if button.text=="警戒前進":ck("advance matches exact variant",rect.position.x==566 and not strip.intersects(rect) if expected=="vc-59f3607d0a76" else rect.position.x==140 and strip.encloses(rect))
   if button.text=="取消選取":ck("cancel selection matches exact variant",not strip.encloses(rect) if expected=="vc-59f3607d0a76" else strip.encloses(rect))
   row.buttons.append({"text":button.text,"rect":str(rect),"fully_inside_strip":strip.encloses(rect)})
 ck("strict current authority captured",Codec.capture_result(g).ok)
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  var file=out+"/mixed-army.png"
  ck("real engine PNG captured",root.get_texture().get_image().save_png(file)==OK)
  row.sha256=FileAccess.get_sha256(file)
 rows.append(row)
 var failed=checks.filter(func(c):return not c.passed).size()
 var report={"build":g.Rules.BUILD_ID,"scope":"Exact official Godot Web PCK loaded natively. Same Battle scenario tick200 and mixed spear/archer selection. Not browser or physical iPhone.","checks":checks,"failed":failed,"rows":rows,"complete":true}
 FileAccess.open(out+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print(JSON.stringify({"build":g.Rules.BUILD_ID,"checks":checks,"failed":failed}))
 g.free();await process_frame;quit(1 if failed>0 else 0)
