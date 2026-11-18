extends SceneTree
const Icons=preload("res://scripts/command_icons.gd")
var checks=[]
func c(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
func settle():
 for i in 4:await process_frame
func touch(p,down,index):
 var e=InputEventScreenTouch.new();e.position=p;e.pressed=down;e.index=index;root.push_input(e);await settle()
func fits(b):
 var text_width=0.0
 for line in b.text.split("\n"):text_width=maxf(text_width,b.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,b.get_theme_font_size("font_size")).x)
 return b.size.x>=ceilf(text_width)+b.get_theme_stylebox("normal").get_minimum_size().x+b.get_theme_constant("icon_max_width")+b.get_theme_constant("h_separation")
func run():
 root.size=Vector2i(390,844)
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();await settle()
 var unique={}
 for kind in Icons.ICONS:
  var texture=Icons.ICONS[kind];unique[texture.resource_path]=true
  c("actual model portrait path "+kind,texture.resource_path=="res://assets/mature/ui/portraits/"+kind+".png" and texture.get_width()==256 and texture.get_height()==256)
 c("sixteen distinct kind portraits",unique.size()==16)
 for size in [Vector2i(320,568),Vector2i(390,844),Vector2i(640,360)]:
  root.size=size;g._layout_ui();g._select([g._first(0,"villager").id]);await settle()
  var house=null;var locked=null
  for b in g.actions.get_children():
   if b is Button and b.get_meta("command_icon_kind","")=="house":house=b
   if b is Button and b.disabled and b.has_meta("command_icon_kind"):locked=b
  var all_build_fit=true;var count_build=0
  for b in g.actions.get_children():
   if b is Button and b.has_meta("command_icon_kind"):
    all_build_fit=all_build_fit and fits(b);count_build+=1
  c("all nine build labels reserve full 40px portrait "+str(size),all_build_fit and count_build==9)
  c("build portrait 40px and name price retained "+str(size),house!=null and house.get_theme_constant("icon_max_width")==40 and house.text.begins_with(g.Rules.NAMES.house+"\n"+g.Rules.cost_label("house")))
  c("locked building portrait visibly disabled "+str(size),locked!=null and locked.get_theme_color("icon_disabled_color").a<1.0 and locked.icon!=null and locked.text.contains("需城防時代"))
  g.action_scroll.ensure_control_visible(house);await settle()
  var p=house.get_global_rect().get_center()
  await touch(p,true,71);await touch(p+Vector2(5,0),true,72);await touch(p+Vector2(5,0),false,72);await touch(p,false,71)
  c("two finger portrait press never builds "+str(size),g.build_mode=="" and g.commands.is_empty())
  var keep=g._first(0,"town_center");g._select([keep.id]);await settle()
  var train=null
  for b in g.actions.get_children():
   if b is Button and b.text.begins_with("訓練村民\n"):train=b
  g.action_scroll.ensure_control_visible(train);await settle()
  c("40px recruit portrait fully reachable "+str(size),train.get_theme_constant("icon_max_width")==40 and g.action_scroll.get_global_rect().encloses(train.get_global_rect()) and train.size.y>=44)
  var bank=g.economy.bank_milli(0).duplicate(true);var q=keep.queue.size()
  await touch(train.get_global_rect().get_center(),true,73);await touch(train.get_global_rect().get_center(),false,73)
  c("single portrait press submits exactly one train "+str(size),g.commands.size()==1 and g.commands[0].type=="train" and g.commands[0].kind=="villager")
  g._tick(g.Rules.TICK)
  c("portrait recruits once with ordinary price "+str(size),keep.queue.size()==q+1 and bank.food-g.economy.bank_milli(0).food==g.Rules.COSTS.villager.food*1000)
 # Controlled owned producer for repeat UI; no research/price changes.
 var barracks=g._spawn("barracks",0,Vector3(-17,0,17));g._update_vision();g._select([barracks.id]);await settle()
 var repeat=g.repeat_train_button
 c("repeat training uses actual configured troop portrait",repeat!=null and repeat.icon==Icons.ICONS[g.Rules.PRODUCES.barracks] and repeat.get_meta("command_icon_kind")==g.Rules.PRODUCES.barracks and repeat.text.contains(g.Rules.cost_label(g.Rules.PRODUCES.barracks)))
 for kind in g.Rules.UNIT_KINDS:
  var button=g._button("訓練"+g.Rules.NAMES[kind]+"\n"+g.Rules.cost_label(kind),func():pass,100)
  Icons.apply(button,kind,true);g.actions.add_child(button);await settle()
  c("every troop price reserves full portrait "+kind,fits(button) and button.get_theme_constant("icon_max_width")==40)
  button.queue_free();await settle()
 var dense=g._button("短",func():pass,100);Icons.apply(dense,"siege");g.actions.add_child(dense);await settle()
 dense.text="攻城車總覽 長標題與數量999\n木材160 鐵礦70";await settle()
 c("dynamic dense list reserves full 32px portrait",fits(dense) and dense.get_theme_constant("icon_max_width")==32)
 dense.queue_free()
 c("economy audit remains conserved",g.economy.audit().ok)
 var failed=checks.filter(func(x):return not x.passed).size()
 print(JSON.stringify({"suite":"command_portraits_contract","checks":checks,"failed":failed,"scope":"Actual-model portrait mapping, native synthetic touch at three mobile viewports, ordinary paid recruitment; not physical phone validation."}));g.free();quit(1 if failed else 0)
