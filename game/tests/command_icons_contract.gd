extends SceneTree
const Icons=preload("res://scripts/command_icons.gd")
const Content=preload("res://scripts/bal01_content.gd")
var checks=[]
func check(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
func settle():
 for i in 4:await process_frame
func touch(p,down,id=31):
 var e=InputEventScreenTouch.new();e.position=p;e.pressed=down;e.index=id;root.push_input(e);await settle()
func run():
 root.size=Vector2i(390,844)
 for kind in Content.UNITS.keys()+Content.BUILDINGS.keys():
  check("icon texture present "+kind,Icons.ICONS.has(kind) and Icons.ICONS[kind].get_width()==256 and Icons.ICONS[kind].get_height()==256)
 var plain=Button.new();plain.text="unchanged";Icons.apply(plain,"unknown");check("unknown keeps original text and no icon",plain.text=="unchanged" and plain.icon==null);plain.free()
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();await settle()
 for size in [Vector2i(320,568),Vector2i(390,844),Vector2i(640,360)]:
  root.size=size;g._layout_ui();var keep=g._first(0,"town_center");g._select([keep.id]);await settle()
  var train=null
  for b in g.actions.get_children():
   if b is Button and b.text.begins_with("訓練村民\n"):train=b
  check("train text cost icon retained "+str(size),train!=null and train.icon==Icons.ICONS.villager and train.text=="訓練村民\n"+g.Rules.cost_label("villager"))
  g.action_scroll.ensure_control_visible(train);await settle()
  check("train reachable 44px target "+str(size),train.size.y>=44 and g.action_scroll.get_global_rect().encloses(train.get_global_rect()))
  var pos=train.get_global_rect().position+Vector2(18,train.size.y/2);var count=g.commands.size()
  await touch(pos,true);await touch(pos,false)
  check("icon touch queues one normal train "+str(size),g.commands.size()==count+1 and g.commands.back().type=="train" and g.commands.back().kind=="villager")
  g.commands.clear()
  train.disabled=true;await touch(pos,true,34);await touch(pos,false,34)
  check("disabled icon cannot queue train "+str(size),g.commands.is_empty());train.disabled=false
  await touch(pos,true,32)
  var drag=InputEventScreenDrag.new();drag.index=32;drag.position=pos+Vector2(-70,0);drag.relative=Vector2(-70,0);root.push_input(drag);await settle();await touch(drag.position,false,32)
  check("icon strip drag cancels command "+str(size),g.commands.is_empty())
  var worker=g._first(0,"villager");g._select([worker.id]);await settle()
  var build=null
  for b in g.actions.get_children():
   if b is Button and b.get_meta("command_icon_kind","")=="house":build=b
  g.action_scroll.ensure_control_visible(build);await settle()
  check("build text cost icon target retained "+str(size),build!=null and build.icon==Icons.ICONS.house and build.text.begins_with(g.Rules.NAMES.house+"\n"+g.Rules.cost_label("house")) and build.size.y>=44 and g.action_scroll.get_global_rect().encloses(build.get_global_rect()))
  await touch(build.get_global_rect().position+Vector2(18,build.size.y/2),true,33);await touch(build.get_global_rect().position+Vector2(18,build.size.y/2),false,33)
  check("icon touch starts ordinary house placement "+str(size),g.build_mode=="house" and g.commands.is_empty());g._cancel_mode();await settle()
 var failed=checks.filter(func(c):return not c.passed).size();print(JSON.stringify({"suite":"command_icons_contract","checks":checks,"failed":failed,"scope":"Native synthetic touch, real button rectangles and ordinary queued commands; actual-model portraits, not new artwork or physical phone."}));g.free();quit(1 if failed else 0)
