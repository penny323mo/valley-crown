extends SceneTree
var g
var rows=[]
var checks=[]
func check(name,ok):
 checks.append({"name":name,"passed":bool(ok)})
 if not ok:push_error(name)
func primary_train():
 for b in g.actions.get_children():
  if b is Button and b.get_meta("primary_train",false):return b
 return null
func touch(point,pressed,index=0):
 var e=InputEventScreenTouch.new();e.index=index;e.position=point;e.pressed=pressed;root.push_input(e)

func _initialize():call_deferred("run")
func settle():
 g._update_hud();g._layout_ui();await process_frame;await process_frame;g._layout_ui();await process_frame
func snapshot(label):
 var r=g.action_scroll.get_global_rect();var buttons=[]
 for b in g.actions.get_children():
  if b is Button and b.is_visible_in_tree():
   var q=b.get_global_rect();var intersection=q.intersection(r)
   buttons.append({"text":b.text,"rect":str(q),"visible_width":maxf(0,intersection.size.x),"full_width":q.size.x,"enabled":not b.disabled,"icon":b.icon!=null,"right_margin":b.get_theme_stylebox("normal").get_content_margin(SIDE_RIGHT)})
 var row={"label":label,"tick":g.tick_count,"size":str(root.size),"bottom":str(g.hud_bottom.get_global_rect()),"top":str(g.hud_top.get_global_rect()),"strip":str(r),"offset":g.action_scroll.scroll_horizontal,"max":g.action_scroll.get_h_scroll_bar().max_value,"page":g.action_scroll.get_h_scroll_bar().page,"buttons":buttons,"selected":g.selected.duplicate(),"commands":g.commands.duplicate(true)}
 rows.append(row);print("UI "+JSON.stringify(row))
func swipe():
 var r=g.action_scroll.get_global_rect();var a=r.get_center()+Vector2(r.size.x*.35,0);var b=a-Vector2(r.size.x*.65,0)
 var e=InputEventScreenTouch.new();e.index=0;e.position=a;e.pressed=true;root.push_input(e)
 var d=InputEventScreenDrag.new();d.index=0;d.position=b;d.relative=b-a;root.push_input(d)
 e=InputEventScreenTouch.new();e.index=0;e.position=b;e.pressed=false;root.push_input(e)
 await process_frame;await process_frame
func button_named(prefix):
 for b in g.actions.get_children():
  if b is Button and b.text.begins_with(prefix):return b
 return null
func visible(b):
 return b!=null and g.action_scroll.get_global_rect().encloses(b.get_global_rect())
func tap(b):
 var point=b.get_global_rect().get_center();touch(point,true);touch(point,false);await settle()
func run():
 g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";root.add_child(g);g.set_process(false);g.test_mode=true;await process_frame
 var worker=g._first(0,"villager");var home=g._first(0,"town_center")
 var initial=g.economy.bank_milli(0).duplicate(true)
 for size in [Vector2i(640,360),Vector2i(390,844)]:
  root.size=size;g._select([worker.id]);await settle()
  var b=button_named("兵營");var tries=0
  while not visible(b) and tries<8:
   await swipe();tries+=1
  check("normal strip swipe reaches barracks "+str(size),visible(b))
  if not visible(b):g.free();quit(1);return
  await tap(b)
  check("real build tap resets changed mode to confirmation "+str(size),g.build_mode=="barracks" and g.action_scroll.scroll_horizontal==0 and visible(g.build_confirm))
  check("suggested preview is not silently confirmed "+str(size),not g.build_preview_held and g.build_confirm.disabled and g.commands.is_empty() and g.economy.bank_milli(0)==initial)
  await swipe();var offset=g.action_scroll.scroll_horizontal
  check("build mode can intentionally inspect trailing controls "+str(size),offset>0)
  await settle()
  check("same build HUD refresh preserves deliberate scroll "+str(size),g.action_scroll.scroll_horizontal==offset)
  g.pointer_world=home.pos;g._update_ghost();await settle()
  check("preview validity change preserves same mode scroll "+str(size),g.action_scroll.scroll_horizontal==offset and g.build_confirm.disabled)
  g._cancel_mode();await settle()
  check("cancel returns to first worker action "+str(size),g.build_mode.is_empty() and g.action_scroll.scroll_horizontal==0 and visible(button_named("民居")))
  await swipe();var ordinary=g.action_scroll.scroll_horizontal;g._select([worker.id]);await settle()
  check("same explicit worker selection keeps scroll "+str(size),g.action_scroll.scroll_horizontal==ordinary)
  g._start_build("barracks");await settle();await swipe()
  g._start_build("house");await settle()
  check("different recipe starts new confirmation context "+str(size),g.build_mode=="house" and g.action_scroll.scroll_horizontal==0 and visible(g.build_confirm))
  # Active old scroll must not shift the replacement row on a late event.
  var start=g.action_scroll.get_global_rect().get_center();touch(start,true)
  var d=InputEventScreenDrag.new();d.index=0;d.position=start-Vector2(80,0);d.relative=Vector2(-80,0);root.push_input(d)
  g._cancel_mode();await settle()
  d=InputEventScreenDrag.new();d.index=0;d.position=start-Vector2(140,0);d.relative=Vector2(-60,0);root.push_input(d);touch(d.position,false);await settle()
  check("late canceled build drag cannot revive old offset or command "+str(size),g.action_scroll.scroll_horizontal==0 and g.commands.is_empty() and g.economy.bank_milli(0)==initial)
 # Same IDs entering/leaving producer targeting must retire pending primary reveal.
 g._select([home.id]);g._start_ground_rally(home.id);await settle()
 check("rally starts its own visible cancel context",g.rally_building==home.id and g.action_scroll.scroll_horizontal==0 and visible(button_named("取消集合點")))
 g._cancel_mode();await settle()
 check("leaving rally reveals ordinary producer primary",visible(primary_train()))
 g._select([worker.id]);await settle();g._start_build("wall");await settle();await swipe();var offset=g.action_scroll.scroll_horizontal
 g._update_hud();await settle()
 check("same wall preview is not repeatedly reset",g.action_scroll.scroll_horizontal==offset)
 g._cancel_mode();await settle()
 g._select([home.id]);g._start_ground_rally(home.id);g._cancel_mode();await settle()
 check("same frame home rally cancel retires old reveal receivers",g.action_reveal_receivers.is_empty() and g.action_reveal_ids.is_empty() and visible(primary_train()))
 g._start_box_select(false);await settle();var key=g.action_mode_identity.duplicate()
 g._start_box_select(true);await settle()
 check("military box filter is a distinct command context",g.action_mode_identity!=key and g.action_scroll.scroll_horizontal==0 and visible(button_named("取消框選")))
 g._cancel_mode();var scout=g._first(0,"scout");g._select([scout.id]);await settle()
 g._start_formation_command("spread");await settle();key=g.action_mode_identity.duplicate()
 g._start_formation_command("line");await settle()
 check("advance formation change updates semantic context",g.action_mode_identity!=key and g.action_scroll.scroll_horizontal==0)
 g._start_tactical_route();await settle();await swipe();offset=g.action_scroll.scroll_horizontal;key=g.action_mode_identity.duplicate()
 g.tactical_draft.append(home.pos);g.action_key="";await settle()
 check("adding a route draft point preserves mode and user offset",g.action_mode_identity==key and g.action_scroll.scroll_horizontal==offset)
 g._cancel_mode();await settle()
 check("mode transitions never spend or enqueue",g.commands.is_empty() and g.economy.bank_milli(0)==initial and g.economy.audit().ok)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"command_mode_scroll_contract","checks":checks,"failed":failed,"scope":"Fresh practice, two logical phone sizes, real root touch barracks entry and scrolling; UI-only mode/recipe/cancel guards. Paid build/birth covered by unchanged command_context_scroll_contract and native journey. Not physical phone validation."}))
 g.free();quit(1 if failed else 0)
