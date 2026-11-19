extends SceneTree
var rows=[]
func check(name,value):
 rows.append([name,bool(value)])
 if not value:push_error(name)
func _initialize():call_deferred("run")
func settle():
 for i in 5:await process_frame
func tap(p,index):
 for pressed in [true,false]:
  var e=InputEventScreenTouch.new();e.position=p;e.index=index;e.pressed=pressed;root.push_input(e);await process_frame
 await settle()
func run():
 for dims in [Vector2i(320,568),Vector2i(390,844),Vector2i(640,360),Vector2i(844,390)]:
  root.size=dims
  var shell=load("res://main_menu.tscn").instantiate();root.add_child(shell);await settle()
  shell._choose_battle("breach");shell._start_match();await settle()
  var g=shell.match_node;g.set_process(false);g._refresh_control_point_marker()
  var scope=str(dims);var b=g.objective_button
  check(scope+" actual objective button visible with location cue",b.is_visible_in_tree() and b.text.begins_with("定位") and b.size.y>=44 and root.get_visible_rect().encloses(b.get_global_rect()))
  var old=g.camera_focus;var units=g.selected.duplicate();var fog=g.visible_cells[0].duplicate();var commands=g.commands.duplicate(true);var bank=g.economy.bank_milli(0).duplicate(true);var scale=g.camera_zoom
  await tap(b.get_global_rect().get_center(),11)
  check(scope+" ordinary first objective touch sets camera and visible return cue",g.camera_focus==g.breach_mission.target() and old!=g.camera_focus and b.text.begins_with("回到所選"))
  await tap(b.get_global_rect().get_center(),12)
  var found=false
  for u in units:
   var r=g.faction_views[0].get_record(u)
   if r.pos==g.camera_focus:found=true
  check(scope+" ordinary second touch frames a real selected member",found and b.text.begins_with("定位"))
  check(scope+" selection fog commands bank and zoom unchanged",g.selected==units and g.visible_cells[0]==fog and g.commands==commands and g.economy.bank_milli(0)==bank and g.camera_zoom==scale)
  g._select([]);g._refresh_control_point_marker()
  await tap(b.get_global_rect().get_center(),13);await tap(b.get_global_rect().get_center(),14)
  check(scope+" no unit offers only original objective action",g.camera_focus==g.breach_mission.target() and b.text.begins_with("定位"))
  shell.free();await settle()
 for mission in ["expedition","escort"]:
  for dims in [Vector2i(320,568),Vector2i(640,360)]:
   root.size=dims
   var shell=load("res://main_menu.tscn").instantiate();root.add_child(shell);await settle()
   shell._choose_battle(mission);shell._start_match();await settle()
   var g=shell.match_node;g.set_process(false)
   var worker=g._first(0,"villager");var s=g.camera.unproject_position(worker.pos+Vector3(0,0.6,0))
   await tap(s,21)
   var b=g.objective_button
   check(mission+" "+str(dims)+" normal worker selection remains authored",g.selected==[worker.id])
   if mission=="expedition":
    # Initial Expedition already centers the home objective; observe the
    # displayed action, then verify that its target matches that label.
    var returns=b.text.begins_with("回到所選")
    await tap(b.get_global_rect().get_center(),24)
    check(mission+" "+str(dims)+" home stage action matches its visible cue",g.camera_focus==(worker.pos if returns else g._authored_objective_position()) and g.selected==[worker.id])
    # Controlled stage boundary only, not a claim of played progression.
    g.frontier_expedition.stage=1;g._refresh_control_point_marker();await settle()

   var button_font=b.get_theme_font("font");var button_size=b.get_theme_font_size("font_size")
   check(mission+" "+str(dims)+" action and mission header both fit",button_font.get_string_size(b.text.split("\n")[0],HORIZONTAL_ALIGNMENT_LEFT,-1,button_size).x<=b.size.x-16)
   await tap(b.get_global_rect().get_center(),22)
   check(mission+" "+str(dims)+" ordinary objective first and return cue",g.camera_focus==g._authored_objective_position() and b.text.begins_with("回到所選"))
   check(mission+" "+str(dims)+" return and mission header both fit",button_font.get_string_size(b.text.split("\n")[0],HORIZONTAL_ALIGNMENT_LEFT,-1,button_size).x<=b.size.x-16)
   await tap(b.get_global_rect().get_center(),23)
   check(mission+" "+str(dims)+" real return retains exact worker and no authority",g.selected==[worker.id] and g.camera_focus==worker.pos and g.commands.is_empty())
   shell.free();await settle()
 for mission in ["breach","escort","expedition"]:
  root.size=Vector2i(320,568)
  var shell=load("res://main_menu.tscn").instantiate();root.add_child(shell);await settle()
  shell._choose_battle(mission);shell._start_match();await settle()
  var g=shell.match_node;g.set_process(false);var b=g.objective_button
  var fits=true
  var stage_count={"breach":3,"escort":4,"expedition":6}[mission]
  var m=g.breach_mission if mission=="breach" else (g.frontier_escort if mission=="escort" else g.frontier_expedition)
  for stage in stage_count:
   # Presentation boundary only; no production mission result altered.
   m.stage=stage
   for focus in [Vector3(0,0,0),g._authored_objective_position()]:
    g.camera_focus=focus;g._refresh_control_point_marker();await settle()
    var a=b.get_theme_font("font")
    var w=a.get_string_size(b.text.split("\n")[0],HORIZONTAL_ALIGNMENT_LEFT,-1,b.get_theme_font_size("font_size")).x
    fits=fits and w<=b.size.x-16
    for char in b.text.split("\n")[0]:fits=fits and a.has_char(char.unicode_at(0))
  check(mission+" all first-line stages and action glyphs fit 320x568",fits)
  shell.free();await settle()
 var failures=rows.filter(func(r):return not r[1]).size()
 print(JSON.stringify({"suite":"objective_camera_route_contract","checks":rows.map(func(r):return {"name":r[0],"passed":r[1]}),"failed":failures,"scope":"True native objective button touches and controlled stage/layout boundaries; no browser hardware or new authority."}))
 quit(1 if failures else 0)
