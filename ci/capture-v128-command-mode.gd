extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
var g
var out:String
var rows=[]
var checks=[]
var expected:String
func _initialize():call_deferred("run")
func ck(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
 return bool(v)
func settle():
 g._update_hud();g._layout_ui();await process_frame;await process_frame
func touch(p):
 for down in [true,false]:
  var e=InputEventScreenTouch.new();e.index=0;e.position=p;e.pressed=down;root.push_input(e);await process_frame
func swipe(direction=-1):
 var r=g.action_scroll.get_global_rect();var p=r.get_center()-Vector2(direction*r.size.x*.35,0);var q=p+Vector2(direction*r.size.x*.6,0)
 var e=InputEventScreenTouch.new();e.index=0;e.position=p;e.pressed=true;root.push_input(e)
 var d=InputEventScreenDrag.new();d.index=0;d.position=q;d.relative=q-p;root.push_input(d)
 e=InputEventScreenTouch.new();e.index=0;e.position=q;e.pressed=false;root.push_input(e);await settle()
func labels(node):
 var found=[]
 for c in node.get_children():
  if c is Label and c.is_visible_in_tree():found.append({"text":c.text,"rect":str(c.get_global_rect()),"minimum":str(c.get_combined_minimum_size())})
  found.append_array(labels(c))
 return found
func save(done):
 FileAccess.open(out+"/report.json",FileAccess.WRITE).store_string(JSON.stringify({"build":g.Rules.BUILD_ID,"scope":"Fresh practice, original bank, actual root swipe/tap into barracks preview; one same-stage capture. Native engine, not browser or physical phone.","checks":checks,"failed":checks.filter(func(c):return not c.passed).size(),"rows":rows,"complete":done},"  "))
func shot(name):
 g._camera_update();g._refresh_fog();g._update_visuals(0);await settle()
 var c=Codec.capture_result(g);ck(name+" strict valid authority",c.ok)
 var row={"name":name,"tick":g.tick_count,"bank":g.economy.bank_milli(0),"mode":g.build_mode,"labels":labels(g.ui),"buttons":[],"authority":c.data if c.ok else {},"commands":g.commands.duplicate(true),"viewport":str(root.size)}
 for b in g.actions.get_children():
  if b is Button and b.is_visible_in_tree():row.buttons.append({"text":b.text,"name":b.name,"rect":str(b.get_global_rect()),"fully_inside_strip":g.action_scroll.get_global_rect().encloses(b.get_global_rect()),"disabled":b.disabled,"minimum":str(b.get_combined_minimum_size())})
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  var p=out+"/"+name+".png";ck(name+" PNG",root.get_texture().get_image().save_png(p)==OK);row.path=p;row.sha256=FileAccess.get_sha256(p)
 rows.append(row);save(false)
func run():
 var a=OS.get_cmdline_user_args();out=a[0];expected=a[3];root.size=Vector2i(int(a[1]),int(a[2]));if DirAccess.dir_exists_absolute(out):quit(2);return
 DirAccess.make_dir_recursive_absolute(out);g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";g.history_path=out+"/private-history.json";root.add_child(g);g.set_process(false)
 for i in 200:g._process(g.Rules.TICK)
 var worker=g._first(0,"villager");var home=g._first(0,"town_center");g._select([worker.id]);await settle()
 var button
 for b in g.actions.get_children():
  if b is Button and b.text.begins_with(g.Rules.NAMES.barracks+"\n"):button=b
 if not ck("barracks existing named build action",button!=null):save(true);g.free();quit(1);return
 for i in 12:
  if g.action_scroll.get_global_rect().encloses(button.get_global_rect()):break
  await swipe()
 ck("real swipe changes no authority command",g.commands.is_empty())
 if not ck("barracks reached by real action swipe",g.action_scroll.get_global_rect().encloses(button.get_global_rect())):save(true);g.free();quit(1);return
 await touch(button.get_global_rect().get_center());await settle();ck("actual root tap enters barracks preview",g.build_mode=="barracks")
 await shot("02-barracks-preview")
 var confirm=g.build_confirm.get_global_rect()
 ck("exact build",g.Rules.BUILD_ID==expected)
 ck("actual portrait viewport",root.size==Vector2i(390,844))
 ck("tick, selection and bank unchanged",g.tick_count==200 and g.selected==[worker.id] and g.economy.bank_milli(0).wood==200000)
 ck("confirm geometry matches revision",g.action_scroll.get_global_rect().encloses(confirm) if expected=="vc-59f3607d0a76" else confirm.end.x<=0)
 ck("ledger conserved",g.economy.audit().ok);save(true);g.free();await process_frame;quit(1 if checks.any(func(c):return not c.passed) else 0)
