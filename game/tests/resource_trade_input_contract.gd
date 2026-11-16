extends SceneTree
var g
var checks=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred("run")
func settle():
 for i in 4:await process_frame
func touch(point,pressed):
 var e=InputEventScreenTouch.new();e.position=point;e.pressed=pressed;e.index=0;root.push_input(e,false)
func tap(point):
 touch(point,true);await process_frame;touch(point,false);await settle()
func run():
 for size in [Vector2i(390,844),Vector2i(640,360)]:
  root.size=size;g=load("res://main.tscn").instantiate();g.skirmish_mode="survival";g.history_path="/tmp/trade-input-"+str(Time.get_ticks_usec())
  root.add_child(g);g.set_process(false);g.test_mode=true;await settle()
  var keep=g._first(0,"town_center");g._select([keep.id]);await settle()
  var entry=g.actions.get_node("OpenResourceTrade")
  g.action_scroll.ensure_control_visible(entry);await settle()
  await tap(entry.get_global_rect().get_center())
  var prefix=str(size)+" "
  check(prefix+"real touch opens trade panel",g.context_detail_kind=="trade" and g.trade_content.visible)
  var option=g.trade_buttons.trade_food_stone
  g.context_details_scroll.ensure_control_visible(option);await settle()
  check(prefix+"last recipe fully scrolls into view",g.context_details_scroll.get_global_rect().encloses(option.get_global_rect()))
  await tap(option.get_global_rect().get_center())
  check(prefix+"real recipe touch queues exact trade only",g.commands.size()==1 and g.commands[0].type=="trade" and g.commands[0].from=="food" and g.commands[0].to=="stone")
  await tap(option.get_global_rect().get_center())
  check(prefix+"pending disabled touch cannot duplicate",g.commands.size()==1)
  var close=g.context_details.find_child("CloseBattleDetails",true,false)
  await tap(close.get_global_rect().get_center())
  check(prefix+"real close hides panel without world order",not g.context_details.visible and g.commands.size()==1)
  g._tick(g.Rules.TICK);g._update_hud();await settle()
  check(prefix+"ordinary execution charges correct input",keep.queue.size()==1 and keep.queue[0].trade_to=="stone" and g.economy.bank_milli(0).food==50000)
  check(prefix+"touch flow leaves isolated history untouched",not FileAccess.file_exists(g.history_path))
  g.free();await settle()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"resource_trade_input_contract","checks":checks,"failed":failed,"scope":"Real routed viewport touch at 390x844 and 640x360, not physical-device acceptance"}));quit(1 if failed else 0)
