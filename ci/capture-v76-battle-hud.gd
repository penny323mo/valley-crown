extends SceneTree
## Genuine product presentation exercised through normal selection and UI.
## No gifts, instant construction, revealed fog or fabricated battle victory.
var outputs=[]
var checks=[]
func _initialize():call_deferred("run")
func check(n,v):checks.append({"name":n,"passed":bool(v)})
func settle(g):
 g._update_hud();g._layout_ui()
 for i in 4:await process_frame
 g._layout_ui();await process_frame
func shot(name):
 await process_frame;await process_frame
 if DisplayServer.get_name()=="headless":return
 await RenderingServer.frame_post_draw
 outputs.append({"name":name,"error":root.get_texture().get_image().save_png("/tmp/capture/"+name+".png")})
func run():
 DirAccess.make_dir_recursive_absolute("/tmp/capture")
 root.size=Vector2i(640,360)
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true
 await settle(g)
 g._select([g._first(0,"town_center").id]);await settle(g)
 await shot("landscape-keep-compact")
 check("selection retains real base",g.selected==[g._first(0,"town_center").id])
 g.context_detail_button.pressed.emit();await settle(g)
 check("real details button expands description",g.context_details.visible and g.selection_detail.is_visible_in_tree())
 await shot("landscape-keep-details")
 g._toggle_context_details("");await settle(g)
 check("closing details restores compact summary",not g.context_details.visible and g.selection_summary.is_visible_in_tree())
 root.size=Vector2i(390,844)
 g._select([g._first(0,"villager").id]);await settle(g)
 await shot("portrait-worker-compact")
 root.size=Vector2i(568,320);await settle(g)
 g._message("位置受阻，請選另一處空地。",4.0);await settle(g)
 await shot("short-landscape-feedback")
 g.toast_time=0.0;await settle(g)
 await shot("short-landscape-tutorial-restored")
 var proof={"suite":"battle_hud_capture","build":load("res://scripts/rules.gd").BUILD_ID,"checks":checks,"outputs":outputs,"scope":"Real initial match selection and controlled UI feedback. Unmodified economy, starting units and fog. No natural victory or physical-phone claim."}
 var f=FileAccess.open("/tmp/capture/battle-hud-receipt.json",FileAccess.WRITE);f.store_string(JSON.stringify(proof,"  "));f.close()
 var failed=checks.filter(func(c):return not c.passed).size();print(JSON.stringify(proof));g.queue_free();quit(1 if failed else 0)
