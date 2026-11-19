extends SceneTree
var g
var checks=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred("run")
func settle():
 g._update_hud();g._layout_ui()
 for i in 4:await process_frame
func touch(p,on,index=0):
 var e=InputEventScreenTouch.new();e.index=index;e.position=p;e.pressed=on;root.push_input(e)
func tap(p):
 touch(p,true);await process_frame;touch(p,false);await settle()
func expose(b):
 g.context_details_scroll.ensure_control_visible(b);await settle()
func run():
 for size in [Vector2i(390,844),Vector2i(640,360)]:
  root.size=size;g=load("res://main.tscn").instantiate();g.skirmish_mode="survival";root.add_child(g);g.set_process(false);g.test_mode=true
  var stock={"food":500,"wood":500,"iron":500,"stone":500};g._test_reset([stock,stock.duplicate(true)]);g.set_process(false);await settle()
  var home=g._first(0,"town_center");g._select([home.id]);await settle()
  var entry=g.actions.get_node("OpenResourceTrade");g.action_scroll.ensure_control_visible(entry);await settle();await tap(entry.get_global_rect().get_center())
  check(str(size)+" real touch trade panel",g.context_detail_kind=="trade")
  for kind in g.TradePolicy.RECIPES:
   var b=g.trade_buttons[kind];await expose(b)
   check(str(size)+" complete price and timing reachable "+kind,g.context_details_scroll.get_global_rect().encloses(b.get_global_rect()) and b.text.contains(g.TradePolicy.label(kind)) and b.text.contains("另計排隊") and b.size.y>=44)
  for source in ["iron","stone"]:
   var b=g.trade_buttons["trade_"+source+"_food"];await expose(b)
   check(str(size)+source+" mineral icon retained",b.icon!=null and b.get_meta("command_icon_kind","")=="trade_"+source+"_food")
  var option=g.trade_buttons.trade_stone_food;await expose(option);var p=option.get_global_rect().get_center();var bank=g.economy.snapshot()
  touch(p,true);await process_frame;touch(p+Vector2(4,0),true,1);touch(p,false);touch(p+Vector2(4,0),false,1);await settle()
  check(str(size)+" second finger cancels without debit",g.commands.is_empty() and g.economy.snapshot()==bank)
  await expose(option);p=option.get_global_rect().get_center();touch(p,true);await process_frame;g._select([g._first(0,"villager").id]);await settle();touch(p,false);await settle()
  check(str(size)+" held selection change cannot pay",g.commands.is_empty() and g.economy.snapshot()==bank)
  g._select([home.id]);await settle();g._open_trade_panel(home.id);await settle();await expose(option);p=option.get_global_rect().get_center();touch(p,true);await process_frame;g._toggle_context_details("trade");await settle();touch(p,false);await settle()
  check(str(size)+" held panel close cannot pay",g.commands.is_empty() and g.economy.snapshot()==bank)
  g._open_trade_panel(home.id);await settle();await expose(option);await tap(option.get_global_rect().get_center())
  check(str(size)+" fresh tap submits exact mineral sale",g.commands.size()==1 and g.commands[0].type=="trade" and g.commands[0].from=="stone" and g.commands[0].to=="food")
  await tap(option.get_global_rect().get_center());check(str(size)+" pending duplicate tap suppressed",g.commands.size()==1)
  for i in 300:g._tick(g.Rules.TICK)
  check(str(size)+" real sale debits100 and credits60 after processing",g.economy.bank_milli(0).stone==400000 and g.economy.bank_milli(0).food==560000 and home.queue.is_empty() and g.economy.audit().ok)
  g.free();await process_frame
 var failed=checks.filter(func(c):return not c.passed).size();print(JSON.stringify({"suite":"mineral_trade_input_contract","checks":checks,"failed":failed,"scope":"Controlled-stock actual routed viewport touch and normal paid300tick settlement, not physical iPhone validation"}));quit(1 if failed else 0)
