extends SceneTree
var outputs=[]
var checks=[]
func _initialize():call_deferred("run")
func check(n,v):checks.append({"name":n,"passed":bool(v)})
func shot(name):
 await process_frame;await process_frame
 if DisplayServer.get_name()=="headless":return
 await RenderingServer.frame_post_draw
 outputs.append({"name":name,"error":root.get_texture().get_image().save_png("/tmp/capture/"+name+".png")})
func run():
 DirAccess.make_dir_recursive_absolute("/tmp/capture")
 root.size=Vector2i(640,360)
 var shell=load("res://main_menu.tscn").instantiate();root.add_child(shell);await process_frame
 shell._choose_battle("standard");shell._show_page("battlefield");await shot("battlefield-selection")
 shell.buttons.get_node("LayoutWoodlandButton").pressed.emit()
 root.size=Vector2i(390,844);shell._layout();await shot("woodland-briefing")
 root.size=Vector2i(640,360)
 shell._replace_match();var g=shell.match_node;g.set_process(false);g.test_mode=true
 check("actual menu launches woodland",g.layout_id=="woodland")
 await shot("woodland-initial-fog")
 shell.queue_free();await process_frame
 for id in ["valley","woodland"]:
  g=load("res://main.tscn").instantiate();g.layout_id=id;root.add_child(g);g.set_process(false);g.test_mode=true
  await process_frame
  # Explicit reveal for comparative authored layout, not a natural scouting claim.
  for team in [0,1]:g.visible_cells[team].fill(1);g.explored_cells[team].fill(1)
  g._publish_faction_views();g._select([]);g.camera_focus=Vector3.ZERO;g.camera_zoom=38;g._camera_update();g._update_visuals(.016);g._refresh_fog();g.ui.hide()
  var overlay=CanvasLayer.new();root.add_child(overlay)
  var panel=PanelContainer.new();panel.position=Vector2(8,8);overlay.add_child(panel)
  var label=Label.new();label.text=("CLASSIC VALLEY" if id=="valley" else "TWIN-WING WOODLAND")+" · REVEALED MIDFIELD\nActual authored initial layout. Not natural scouting / victory.";label.add_theme_font_size_override("font_size",13);panel.add_child(label)
  await shot(id+"-revealed-overview")
  check(id+" layout retained",g.layout_id==id)
  g.queue_free();overlay.queue_free();await process_frame
 var proof={"suite":"battlefield_capture","build":load("res://scripts/rules.gd").BUILD_ID,"checks":checks,"outputs":outputs,"scope":"Real menu and initial fog; explicitly revealed comparative map overviews. No natural victory or physical-phone claim."}
 var f=FileAccess.open("/tmp/capture/battlefield-receipt.json",FileAccess.WRITE);f.store_string(JSON.stringify(proof,"  "));f.close()
 var failed=checks.filter(func(c):return not c.passed).size();print(JSON.stringify(proof));quit(1 if failed else 0)
