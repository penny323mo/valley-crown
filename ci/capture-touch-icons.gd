extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var g
var out=""
var metadata_only=false
var checks=[]
var report={"captures":[],"scope":"Actual ordinary practice seed, normal paid barracks construction, AI scheduling disabled for UI demonstration. Native viewport synthetic touch and actual product callbacks, not a physical phone/browser test. No HP, stock, fog or outcome overrides; no save operations."}
func _initialize():call_deferred("run")
func check(label,ok):checks.append({"name":label,"passed":bool(ok)});return bool(ok)
func settle():await process_frame;await process_frame
func touch(p,down,index=10):
 var e=InputEventScreenTouch.new();e.position=p;e.pressed=down;e.index=index;root.push_input(e,false)
func drag(p,delta,index=10):
 var e=InputEventScreenDrag.new();e.position=p;e.relative=delta;e.index=index;root.push_input(e,false)
func tick():g._tick(Rules.TICK);g._update_visuals(Rules.TICK)
func button(prefix):
 for b in g.actions.get_children():
  if b is Button and b.text.begins_with(prefix):return b
 return null
func visible_button(b):
 return b!=null and b.is_visible_in_tree() and g.action_scroll.get_global_rect().encloses(b.get_global_rect()) and b.icon!=null and not b.text.is_empty()
func shot(name):
 g._camera_update();g._refresh_fog();g._update_visuals(0);g._update_hud();await settle()
 var buttons=[]
 for b in g.actions.get_children():
  if b is Button:buttons.append({"text":b.text,"icon":b.icon.resource_path if b.icon else "","rect":str(b.get_global_rect()),"fully_visible":g.action_scroll.get_global_rect().encloses(b.get_global_rect())})
 var count=g.drag_rect.get_node_or_null("SelectionCount")
 var row={"name":name,"tick":g.tick_count,"selected":g.selected.duplicate(),"bank":g.economy.bank_milli(0),"camera":str(g.camera_focus),"zoom":g.camera_zoom,"buttons":buttons,"box_visible":g.drag_rect.visible,"box_count":count.text if count else "","metadata_only":metadata_only}
 if not metadata_only:
  await RenderingServer.frame_post_draw
  var p=out+"/"+name+".png";check(name+" PNG",root.get_texture().get_image().save_png(p)==OK);row.file=p;row.sha256=FileAccess.get_sha256(p)
 report.captures.append(row)
func finish():
 report.checks=checks;report.failed=checks.filter(func(c):return not c.passed).size()
 var f=FileAccess.open(out+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close();print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));quit(1 if report.failed else 0)
func run():
 var args=OS.get_cmdline_user_args();out=args[0] if args.size()>0 else "/tmp/touch-icons-capture"
 if DirAccess.dir_exists_absolute(out):quit(2);return
 DirAccess.make_dir_recursive_absolute(out);metadata_only=DisplayServer.get_name()=="headless" or "--metadata-only" in args
 root.size=Vector2i(390,844);report.build=Rules.BUILD_ID;report.driver_sha256=FileAccess.get_sha256(get_script().resource_path)
 for p in ["game","command_icons","rules"]:report[p+"_sha256"]=FileAccess.get_sha256("res://scripts/"+p+".gd")
 g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";root.add_child(g);g.set_process(false);g.ai_enabled=false;await settle()
 var worker=g._first(0,"villager");g.camera_focus=worker.pos;g.camera_zoom=22;g._camera_update();g._layout_ui();g._select([worker.id]);await settle()
 var home=button("民居\n");g.action_scroll.ensure_control_visible(home);await settle()
 if not check("villager construction icon with name and real cost visible",visible_button(home) and home.text.contains(Rules.cost_label("house"))):finish();return
 await shot("01-villager-build-icons")
 # Slow stationary empty-ground tap, no command button. Use real monotonic hold.
 var p=Vector2.ZERO
 for y in range(250,500,20):
  for x in range(90,260,20):
   var q=Vector2(x,y)
   if g._box_point_in_world(q) and g._pick(q)<0:p=q;break
  if p!=Vector2.ZERO:break
 if not check("empty world target exists",p!=Vector2.ZERO):finish();return
 var before=g.commands.size();touch(p,true);var start=Time.get_ticks_msec()
 while Time.get_ticks_msec()-start<380:await process_frame;OS.delay_msec(1)
 touch(p,false);await settle()
 check("slow stationary tap submits one contextual move",g.commands.size()==before+1 and g.commands.back().type=="order" and g.commands.back().ids==[worker.id])
 tick()
 # No time threshold: immediate single-finger box of normal starting villagers.
 var villagers=[]
 for u in g.entities:
  if u.alive and u.team==0 and u.kind=="villager":villagers.append(u)
 var center=Vector3.ZERO
 for u in villagers:center+=u.pos
 center/=villagers.size();g.camera_focus=center;g._camera_update();await settle()
 var rect=Rect2(g.camera.unproject_position(villagers[0].pos+Vector3(0,.6,0)),Vector2.ZERO)
 for u in villagers:rect=rect.expand(g.camera.unproject_position(u.pos+Vector3(0,.6,0)))
 rect=rect.grow(14)
 if not check("normal villager box fits world viewport",g._box_point_in_world(rect.position) and g._box_point_in_world(rect.end)):finish();return
 before=g.commands.size();var focus=g.camera_focus
 touch(rect.position,true);drag(rect.end,rect.size);await settle()
 var expected=g._box_selection_ids(rect);var count=g.drag_rect.get_node_or_null("SelectionCount")
 check("quick drag displays actual nonempty count",g.drag_rect.visible and count!=null and count.text==str(expected.size()) and expected.size()>1)
 await shot("02-quick-box-preview-count")
 touch(rect.end,false);await settle()
 check("quick box selects same units without order or camera pan",g.selected==expected and g.commands.size()==before and g.camera_focus==focus)
 await shot("03-box-selected-result")
 # Same-direction paired pan with tiny span jitter, no queued orders.
 var selection=g.selected.duplicate();var zoom=g.camera_zoom;before=g.commands.size();focus=g.camera_focus
 var a=Vector2(100,320);var b=Vector2(260,320)
 touch(a,true);touch(b,true,11)
 for i in range(1,7):
  drag(a+Vector2(i*3,0),Vector2(3,0));drag(b+Vector2(i*3+(2 if i%2 else -2),0),Vector2(3,0),11)
 touch(a+Vector2(18,0),false);touch(b+Vector2(16,0),false,11);await settle()
 check("paired pan moves camera without jitter zoom or command",g.camera_focus!=focus and g.camera_zoom==zoom and g.commands.size()==before and g.selected==selection)
 report.paired_pan={"before":str(focus),"after":str(g.camera_focus),"zoom_before":zoom,"zoom_after":g.camera_zoom,"orders_unchanged":g.commands.size()==before}
 # Pay and build a real barracks with those normal workers; no fixture building spawn.
 g._select(villagers.map(func(u):return u.id));g.camera_focus=center;g._camera_update();await settle()
 var build=button("兵營\n");g.action_scroll.ensure_control_visible(build);await settle()
 if not check("barracks build action icon and price",visible_button(build)):finish();return
 build.pressed.emit();await settle()
 var site=Vector3.INF
 for z in range(-7,8):
  for x in range(-7,8):
   var q=g._point(g._cell(center+Vector3(x,0,z)));g.pointer_world=q;g._update_ghost()
   var screen=g.camera.unproject_position(q)
   if g.placement_ok and g._box_point_in_world(screen) and g.visible_cells[0][g._cell_index(q)]!=0:site=q;break
  if site!=Vector3.INF:break
 if not check("legal visible ordinary barracks placement",site!=Vector3.INF):finish();return
 var screen=g.camera.unproject_position(site);touch(screen,true);touch(screen,false);await settle()
 if not check("touch placement accepted",g.build_preview_held and g.placement_ok):finish();return
 var bank=g.economy.bank_milli(0).duplicate(true);g.build_confirm.pressed.emit();tick()
 var barracks=g._first(0,"barracks")
 for i in 1200:
  if not barracks.is_empty() and barracks.built:break
  tick();barracks=g._first(0,"barracks")
 if not check("barracks built through normal paid ticks",not barracks.is_empty() and barracks.built and g.economy.bank_milli(0).wood==bank.wood-120000):finish();return
 g._select([barracks.id]);g.camera_focus=barracks.pos;g._camera_update();await settle()
 var train=button("訓練長槍兵\n");g.action_scroll.ensure_control_visible(train);await settle()
 check("producer train icon label and cost visible",visible_button(train) and train.text.contains(Rules.cost_label("spearman")))
 await shot("04-paid-barracks-training-icons")
 finish()
