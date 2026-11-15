extends SceneTree
const OUT="/tmp/capture/"
func _initialize():call_deferred("run")
func shot(g,name):
 g._publish_faction_views();g._update_vision();g._update_visuals(0.0);g._update_hud();g._layout_ui();g._camera_update()
 await process_frame
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image();var error=image.save_png(OUT+name+".png")
 print("CAPTURE ",name," ",image.get_width(),"x",image.get_height()," ",error)
 return error==OK
func run():
 root.size=Vector2i(640,360)
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false);g._skip_tutorial();await process_frame
 var own=g._spawn("archer",0,Vector3.ZERO,true)
 var near=g._spawn("archer",1,Vector3(1,0,0),true)
 var counter=g._spawn("spearman",1,Vector3(3,0,0),true)
 g._update_vision();g._order_advance([own.id],Vector3(8,0,0),0)
 var default_target=g._advance_target(own).id
 g._publish_faction_views();g._select([own.id]);g.camera_focus=Vector3(1.5,0,0);g.camera_zoom=15
 var ok=await shot(g,"native-default-nearest-policy")
 g.compact_menu.show();g._set_shortcut_category("army");var button=g.find_child("TargetPolicy_counter",true,false)
 await process_frame
 g.shortcut_scroll.ensure_control_visible(button)
 ok=await shot(g,"native-army-menu-target-policy-controls") and ok
 button.pressed.emit();g._tick(0.1);g._publish_faction_views();g._select([own.id])
 var opted_target=g._advance_target(own).id
 ok=await shot(g,"native-applied-counter-priority") and ok
 print(JSON.stringify({"build":g.Rules.BUILD_ID,"scope":"Controlled owned archer with enemy archer1m and enemy spearman3m; policy submitted then normal tick. Not natural match or phone acceptance","default_nearest":default_target==near.id,"counter_target":opted_target==counter.id,"policy":own.target_policy,"hud":g.selection_detail.text}))
 ok=ok and default_target==near.id and opted_target==counter.id and own.target_policy=="counter" and g.selection_detail.text.contains("克制優先 1")
 g.queue_free();quit(0 if ok else 1)
