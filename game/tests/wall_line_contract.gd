extends SceneTree
## Controlled UI planning and real command/tick/receipt/restore checks. No phone QA claim.
const Rules=preload("res://scripts/rules.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
var g
var crew=[]
var layout_geometry=[]
var layout_label=""
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred("run")
func fresh(wood=200):
 if is_instance_valid(g):g.free()
 g=load("res://main.tscn").instantiate();g.history_path="/tmp/wall-line-history-%d" % Time.get_ticks_usec()
 root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false
 g._test_reset([{"food":150,"wood":wood,"stone":100,"iron":0},{"food":150,"wood":200,"stone":100,"iron":0}]);g.set_process(false)
 crew=[]
 for e in g.entities:
  if e.alive and e.team==0 and e.kind=="villager":crew.append(e.id)
 crew=crew.slice(0,3)
 g._update_vision();g._publish_faction_views();g._select(crew);g._start_build("wall")
func row(count):
 g.wall_line_count=count
 for distance in range(2,15):
  for dz in range(-distance,distance+1):
   for dx in range(-distance,distance+1):
    g.pointer_world=g._snap_build_position("wall",g._get_entity(crew[0]).pos+Vector3(dx,0,dz))
    if g._build_preview_reason().is_empty():g.build_preview_held=true;return true
 return false
func tick(n=1):
 for i in n:g._tick(Rules.TICK)
func walls():return g.entities.filter(func(e):return e.team==0 and e.kind=="wall")
func press(button):
 button.size=Vector2(160,64);g.all_touch_ids=[7];g.touch_press_epochs={7:1}
 var event=InputEventScreenTouch.new();event.index=7;event.pressed=true;event.position=Vector2(12,12)
 g._button_touch_input(button,event)
func release(button):
 g.all_touch_ids.clear()
 var event=InputEventScreenTouch.new();event.index=7;event.pressed=false;event.position=Vector2(12,12)
 g._button_touch_input(button,event)
func run():
 fresh()
 check("default single segment preserves helper construction",g.wall_line_count==1 and crew.size()>=3)
 g._cycle_wall_line_count();check("explicit row toggle gives two segments",g.wall_line_count==2 and not g.build_preview_held)
 g._cycle_wall_line_count();check("row bounded by selected crew",g.wall_line_count==3)
 g._cycle_wall_line_count();check("row cycles back to single",g.wall_line_count==1)
 check("ordinary visible three segment plot found",row(3))
 if not g._build_preview_reason().is_empty():finish();return
 g._update_ghost();g._update_hud()
 var points=g._wall_line_points()
 check("row preview shows three adjacent two metre footprints",g.ghost.get_children().filter(func(n):return n.visible).size()==3 and points[1]-points[0]==Vector3(2,0,0) and points[2]-points[1]==Vector3(2,0,0))
 check("HUD shows full ninety wood price",g.queue_label.text.contains("90") and g.queue_label.text.contains("3"))
 var bank=g.economy.bank_milli(0).wood
 g._confirm_build();check("confirm queues one existing build per unique worker",g.commands.size()==3 and g.commands.all(func(c):return c.type=="build" and c.ids.size()==1) and g.commands[0].builder!=g.commands[1].builder and g.commands[1].builder!=g.commands[2].builder)
 check("no charge before authoritative execution",g.economy.bank_milli(0).wood==bank)
 var queued=Codec.capture(g);check("pending row remains existing valid checkpoint schema",not queued.is_empty() and Codec.validate(queued))
 g._confirm_build();check("duplicate confirmation cannot requeue",g.commands.size()==3)
 tick();check("all three ordinary paid sites created",walls().size()==3 and g.economy.bank_milli(0).wood==bank-90000)
 check("each worker has independent target",crew.all(func(id):return g._get_entity(id).state=="build") and g._get_entity(crew[0]).target!=g._get_entity(crew[1]).target)
 check("actual row success count displayed",g.toast_label.text.contains("3 / 3") and g.toast_label.text.contains("90"))
 var snap=Codec.capture(g);check("paid row valid checkpoint",not snap.is_empty() and Codec.validate(snap))
 var h=load("res://main.tscn").instantiate();h.history_path="/tmp/wall-line-restored";root.add_child(h);h.set_process(false);h.test_mode=true;h.ai_enabled=false
 check("paid row restores through existing codec",Restore.apply(h,snap))
 h.paused=false
 for i in 2200:
  if walls().all(func(w):return w.built):break
  tick();h._tick(Rules.TICK)
 check("all three workers finish their own ordinary ten-second walls",walls().size()==3 and walls().all(func(w):return w.built and w.build_ticks==200 and w.hp==250))
 check("restored paid row follows identical continuation",Codec.capture(g)==Codec.capture(h))
 check("all receipts fulfilled and economy conserved",walls().all(func(w):return g.economy.receipt_view(w.cost_receipt_id).get("state","")=="fulfilled") if g.economy.has_method("receipt_view") else g.economy.audit().ok)
 h.free()
 fresh();row(3);bank=g.economy.bank_milli(0).wood
 g._cancel_mode();g._confirm_build();tick();check("cancel no sites no debit",walls().is_empty() and g.economy.bank_milli(0).wood==bank)
 fresh(80)
 g.wall_line_count=3;g.build_preview_held=true;g._confirm_build();check("total cost insufficient blocks whole preview",g.commands.is_empty() and g._build_preview_reason().contains("資源不足"))
 fresh();row(3)
 g._rotate_wall_line();check("rotate retires held placement",g.wall_line_vertical and not g.build_preview_held and g.commands.is_empty())
 check("rotated row is axis aligned",g._wall_line_points()[1]-g._wall_line_points()[0]==Vector3(0,0,2))
 fresh();row(3);points=g._wall_line_points()
 var blocker=g._spawn("scout",0,points[2]);g._update_vision();g._publish_faction_views();g._update_hud()
 check("later row obstruction prevents confirmation",g._build_preview_reason().begins_with("第3段"))
 check("clear site includes later row blockers",g._clear_site_plan().any(func(c):return c.ids==[blocker.id]))
 g._confirm_build();check("blocked row does not queue any purchase",g.commands.is_empty())
 g._clear_build_site();check("row clearance remains separate move only",not g.commands.is_empty() and g.commands.all(func(c):return c.type=="order"))
 fresh();row(3);g._confirm_build();bank=g.economy.bank_milli(0).wood
 g._kill(g._get_entity(crew[1]));tick()
 check("dead worker rejects only own site without free work",walls().size()==2 and g.economy.bank_milli(0).wood==bank-60000)
 check("partial result displays actual count and price",g.toast_label.text.contains("2 / 3") and g.toast_label.text.contains("60"))
 fresh(100);row(3)
 # Earlier ordinary storehouse purchase consumes80, leaving20. Row execution must not overdraw.
 var builder=g._get_entity(crew[0]);var house=Vector3.INF
 for distance in range(4,15):
  for dz in range(-distance,distance+1):
   for dx in range(-distance,distance+1):
    var p=g._snap_build_position("storehouse",builder.pos+Vector3(dx,0,dz))
    if house==Vector3.INF and g._placement_reason("storehouse",p,0,builder.id).is_empty():house=p
 check("competing ordinary storehouse site available",house!=Vector3.INF)
 g._submit("build",{"kind":"storehouse","builder":builder.id,"ids":[builder.id],"position":house});g._confirm_build();tick()
 check("same-tick prior spending cannot overdraw row",walls().is_empty() and g.economy.bank_milli(0).wood==20000 and g.economy.audit().ok)
 check("zero-success row reports no row payment",g.toast_label.text.contains("0 / 3") and g.toast_label.text.contains("木材 0"))
 fresh();row(3)
 g._select([crew[0]]);g._confirm_build();check("selection replacement cancels held row",g.build_mode.is_empty() and g.commands.is_empty())
 g._start_build("wall");g._cycle_wall_line_count();check("single worker cannot enable multi row",g.wall_line_count==1)
 g._cancel_mode();g._select(crew);g._start_build("wall");row(3);g.paused=true;g._confirm_build();check("paused row cannot command",g.commands.is_empty());g.paused=false
 g.touch_gesture=true;g._confirm_build();check("camera gesture cannot confirm row",g.commands.is_empty());g.touch_gesture=false
 g._on_web_touch_cancel([]);g._confirm_build();check("web touch cancel retires row",g.commands.is_empty() and g.build_mode.is_empty())
 fresh();row(2);g._update_hud();var held=g.build_confirm;press(held)
 g._kill(g._get_entity(crew[0]));g._publish_faction_views();g._update_hud();release(held)
 check("held confirmation cannot survive selected worker death",g.commands.is_empty())
 fresh();row(3);g._update_hud();held=g.build_confirm;press(held);g._select([crew[0]]);release(held)
 check("held confirmation cannot survive replacement selection",g.commands.is_empty())
 fresh();row(3);g._update_hud();held=g.build_confirm;press(held);g.touch_gesture=true;g.all_touch_ids=[7,8];release(held)
 check("two finger gesture cancels held GUI confirm",g.commands.is_empty())
 fresh();row(3);g._update_hud();held=g.build_confirm;press(held);release(held);release(held)
 check("real GUI touch release submits row exactly once",g.commands.size()==3)
 fresh();row(3);g.short_ui=true;g.compact_ui=true;g._update_hud();g._update_ghost()
 check("short HUD guidance includes quantity and total cost",g.toast_label.text.contains("3") and g.toast_label.text.contains("90"))
 fresh()
 var four=[]
 for e in g.entities:
  if e.alive and e.team==0 and e.kind=="villager":four.append(e.id)
 four=four.slice(0,4);g._cancel_mode();g._select(four);g._start_build("wall")
 g._cycle_wall_line_count();g._cycle_wall_line_count();g._cycle_wall_line_count()
 check("four selected workers allow four segment plan",four.size()==4 and g.wall_line_count==4 and g._wall_line_points().size()==4)
 g._cycle_wall_line_count();check("four segment upper bound cycles to single",g.wall_line_count==1)
 fresh();row(3);g._update_hud();var old_button=g.build_confirm
 # Force an ordinary action-strip replacement; then a distinct newer press
 # reuses the same device index on the replacement button.
 g.action_key="";g._update_hud();var new_button=g.build_confirm;press(new_button)
 release(old_button)
 check("late detached button event preserves newer same-index press",g.gui_touch_press.has(7) and g.gui_touch_press[7].button.get_ref()==new_button)
 release(new_button)
 check("newer replacement button press still confirms exactly once",g.commands.size()==3)
 check("ledger audit remains conserved",g.economy.audit().ok)
 g.free()
 await run_layout()
 finish()
func finish():
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"wall_line_contract","checks":checks,"failed":failed,"geometry":layout_geometry,"scope":"Controlled current game UI planning plus actual paid commands, ticks, travel, construction and checkpoint continuation; no phone or natural battle claim."}))
 if is_instance_valid(g):g.free()
 quit(1 if failed else 0)

# Same four-size 76-check layout regression: actual Control geometry and routed
# synthetic screen touches/drags. Not rendered-image or physical-device QA.
func layout_check(n,v):
 check("layout "+layout_label+" "+n,v)
func layout_settle():
 for i in 5:await process_frame
func layout_touch(p,down):
 var e=InputEventScreenTouch.new();e.index=3;e.position=p;e.pressed=down
 root.push_input(e,true)
func layout_drag(a,b):
 layout_touch(a,true)
 var e=InputEventScreenDrag.new();e.index=3;e.position=b;e.relative=b-a
 root.push_input(e,true);layout_touch(b,false)
func layout_tap(button):
 var p=button.get_global_rect().get_center()
 layout_touch(p,true);layout_touch(p,false)
func layout_reveal(button):
 var viewport=g.action_scroll.get_global_rect()
 for i in 12:
  if viewport.encloses(button.get_global_rect()):return true
  var center=viewport.get_center();var delta=minf(120,viewport.size.x*.35)
  if button.get_global_rect().position.x<viewport.position.x:layout_drag(center-Vector2(delta/2,0),center+Vector2(delta/2,0))
  else:layout_drag(center+Vector2(delta/2,0),center-Vector2(delta/2,0))
  await layout_settle()
 return viewport.encloses(button.get_global_rect())
func layout_row_plot():
 var w=g._get_entity(g._selected_builder())
 for dz in range(-12,13):
  for dx in range(-12,13):
   g.pointer_world=g._snap_build_position("wall",w.pos+Vector3(dx,0,dz))
   if g._build_preview_reason().is_empty():g.build_preview_held=true;return true
 return false
func run_layout():
 for size in [Vector2i(390,844),Vector2i(320,568),Vector2i(568,320),Vector2i(1280,800)]:
  root.size=size;await layout_settle();layout_label=str(size)
  g=load("res://main.tscn").instantiate();g.history_path="user://wall-line-layout-"+str(Time.get_ticks_usec());root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false);await layout_settle()
  var ids=[]
  for e in g.entities:
   if e.team==0 and e.alive and e.kind=="villager" and ids.size()<3:ids.append(e.id)
  g._publish_faction_views();g._select(ids);g._start_build("wall");await layout_settle();g._layout_ui();await layout_settle()
  layout_check("actual viewport requested",root.get_visible_rect().size==Vector2(size))
  var bounds=Rect2(Vector2.ZERO,Vector2(size));var top=g.hud_top.get_global_rect();var bottom=g.hud_bottom.get_global_rect()
  layout_check("top and bottom contained",bounds.encloses(top) and bounds.encloses(bottom))
  layout_check("HUD no overlap with battlefield gap",top.end.y+40<bottom.position.y)
  var count=g.actions.get_node("WallLineCount")
  layout_check("scroll reaches count",await layout_reveal(count))
  layout_check("scroll issues no commands",g.commands.is_empty() and g.wall_line_count==1)
  layout_tap(count);await layout_settle();layout_check("touch count activates once",g.wall_line_count==2)
  count=g.actions.get_node("WallLineCount");layout_check("count still reachable",await layout_reveal(count));layout_tap(count);await layout_settle();layout_check("touch count reaches three",g.wall_line_count==3)
  var direction=g.actions.get_node("WallLineDirection");layout_check("scroll reaches direction",await layout_reveal(direction));layout_tap(direction);await layout_settle();layout_check("touch direction activates once",g.wall_line_vertical and not g.build_preview_held)
  layout_check("UI touches no world build",g.commands.is_empty() and g.selected==ids)
  layout_check("visible legal row fixture found",layout_row_plot());g._update_ghost();g._update_hud();await layout_settle()
  layout_check("scroll back reaches confirm",await layout_reveal(g.build_confirm))
  top=g.hud_top.get_global_rect();bottom=g.hud_bottom.get_global_rect()
  layout_check("row plan HUD stays within viewport",bounds.encloses(top) and bounds.encloses(bottom))
  layout_check("row plan leaves battlefield gap",top.end.y+40<bottom.position.y)
  var overlap=false
  var rects=[]
  for button in g.actions.get_children():
   if button is Button:
    for other in rects:
     if other.intersects(button.get_global_rect()):overlap=true
    rects.append(button.get_global_rect())
  layout_check("row action buttons do not overlap",not overlap)
  var buttons=[]
  for b in g.actions.get_children():
   if b is Button:buttons.append({"text":b.text,"rect":str(b.get_global_rect())})
  layout_geometry.append({"size":str(size),"top":str(top),"bottom":str(bottom),"scroll":str(g.action_scroll.get_global_rect()),"buttons":buttons,"summary":g.selection_summary.text,"queue":g.queue_label.text})
  layout_tap(g.build_confirm);await layout_settle();layout_check("touch confirm exactly three queued commands",g.commands.size()==3)
  layout_check("confirm exits placement without changing selected workers",g.build_mode.is_empty() and g.selected==ids)
  var unique={}
  for command in g.commands:unique[command.builder]=true
  layout_check("UI leaked no extra orders",g.commands.all(func(c):return c.type=="build" and c.kind=="wall") and unique.size()==3)
  g.free();await layout_settle()
