extends SceneTree
var checks=[]
func measure(n,b):
 checks.append({"name":n,"passed":bool(b)})
 if not b:push_error(n)
func _initialize():call_deferred("run")
func settle():
 for i in 4:await process_frame
func tap(p,i):
 for down in [true,false]:
  var e=InputEventScreenTouch.new();e.position=p;e.pressed=down;e.index=i;root.push_input(e);await process_frame
 await settle()
func run():
 for dims in [Vector2i(844,390),Vector2i(640,360)]:
  root.size=dims
  var g=load("res://main.tscn").instantiate();g.set("skirmish_mode","practice");root.add_child(g);g.set_process(false)
  await settle()
  var worker=g._first(0,"villager");g._select([worker.id]);g.toast_time=0;g._layout_ui();await settle()
  var band=Vector2(225,275 if dims.x==844 else 245)
  var wing=Vector2(140,91)
  measure("previous full-width tutorial band now routes world in freed wing "+str(dims),g.tutorial_panel.visible and not g.tutorial_panel.get_global_rect().has_point(wing) and g._box_point_in_world(wing))
  measure("previous footer strip now routes world "+str(dims),not g.hud_bottom.get_global_rect().has_point(band) and g._box_point_in_world(band))
  measure("not a tutorial skip or lost progress "+str(dims),not g.demo_tutorial.skipped and g.tutorial_entry.visible)
  var hints_fit=true
  var achieved=g.demo_tutorial.achieved.duplicate(true)
  for paused_state in [false,true]:
   g.paused=paused_state
   g.demo_tutorial.achieved.clear()
   for index in 11:
    g._refresh_tutorial();await settle()
    if g.tutorial_label.get_line_count()>2:print("OVERFLOW ",dims," ",paused_state," ",index," ",g.tutorial_label.get_line_count()," ",g.tutorial_label.size.x," ",g.tutorial_label.text)
    hints_fit=hints_fit and g.tutorial_label.get_line_count()<=2 and not g.tutorial_label.text.is_empty()
    if index<g.demo_tutorial.KEYS.size():g.demo_tutorial.record(g.demo_tutorial.KEYS[index])
  g.paused=false;g.demo_tutorial.achieved=achieved;g._refresh_tutorial();await settle()
  measure("all 10 short lessons, paused and running, fit two lines "+str(dims),hints_fit)
  var tutorial_rect=g.tutorial_panel.get_global_rect()
  var guidance_rect=g.guidance_detail_button.get_global_rect()
  measure("right card still exposes full details at touch size "+str(dims),tutorial_rect.encloses(guidance_rect) and guidance_rect.size.y>=44 and g.guidance_detail_button.visible)
  await tap(guidance_rect.get_center(),2)
  measure("real tap opens full onboarding details "+str(dims),g.context_details.visible and not g.guidance_detail.text.is_empty())
  var close=g.context_details.find_child("CloseBattleDetails",true,false)
  await tap(close.get_global_rect().get_center(),3)
  var house=g.actions.get_children().filter(func(b):return b is Button and b.get_meta("command_icon_kind","")=="house")[0]
  measure("normal visible build shows icon, price and touch rect "+str(dims),g.action_scroll.get_global_rect().encloses(house.get_global_rect()) and house.get_global_rect().size.y>=44 and house.icon!=null and house.text.contains("木 50"))
  await tap(house.get_global_rect().get_center(),4)
  measure("ordinary touch opens real house placement "+str(dims),g.build_mode=="house" and g.commands.is_empty())
  # Spot is obtained through actual authoritative placement preview; no
  # construction state, bank, prices, success status or positions are injected.
  var found=false
  for y in range(120,230,12):
   for x in range(65,int(dims.x)-65,16):
    var p=Vector2(x,y)
    if not g._box_point_in_world(p):continue
    await tap(p,5)
    g._update_ghost();await settle()
    if g.placement_ok:found=true;break
   if found:break
  measure("actual touch found legal visible placement "+str(dims),found)
  if found:
   var wood=g.economy.bank_milli(0).wood
   var bb=g.build_confirm
   await tap(bb.get_global_rect().get_center(),6)
   g.ai_enabled=false;g._tick(g.Rules.TICK)
   measure("only normal paid construction succeeds "+str(dims),wood-g.economy.bank_milli(0).wood==50000 and not g._first(0,"house").is_empty())
  g._message("出口受阻；請選取單位移開",4);await settle()
  measure("actual urgent feedback retains full width and one-line fit "+str(dims),is_equal_approx(g.tutorial_panel.size.x,float(dims.x-12)) and g.toast_label.visible and g.toast_label.get_line_count()==1)
  g.free();await settle()
 for dims in [Vector2i(568,320),Vector2i(390,844),Vector2i(1024,420)]:
  root.size=dims
  var g=load("res://main.tscn").instantiate();g.set("skirmish_mode","practice")
  root.add_child(g);g.set_process(false)
  await settle();g.toast_time=0;g._layout_ui();await settle()
  measure("unsupported viewport retains original expanded full-width guide "+str(dims),not g.low_landscape_ui and g.tutorial_panel.visible and is_equal_approx(g.tutorial_panel.size.x,float(dims.x-12)))
  g.free();await settle()
 var failed=checks.filter(func(x):return not x.passed).size()
 print(JSON.stringify({"suite":"landscape_hud_contract","checks":checks,"failed":failed,"scope":"Native ordinary HUD, touch placement and controlled guide states; not rendered browser or hardware."}))
 quit(1 if failed else 0)
