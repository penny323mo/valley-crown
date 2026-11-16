extends SceneTree
const OUT="/tmp/capture/"
func _initialize():call_deferred("run")
func shot(menu,name):
 menu._layout()
 await process_frame
 await process_frame
 await RenderingServer.frame_post_draw
 var im=root.get_texture().get_image();var err=im.save_png(OUT+name+".png")
 print("CAPTURE ",name," ",im.get_width(),"x",im.get_height()," ",err)
 return err==OK
func run():
 root.size=Vector2i(640,360)
 var menu=load("res://main_menu.tscn").instantiate()
 menu.checkpoint_path="user://isolated-capture-never-read.json";menu.history_path="user://isolated-history-never-read.json"
 root.add_child(menu);await process_frame
 var ok=await shot(menu,"native-catalogue-home")
 for row in [[0,2,"spearman"],[0,4,"cavalry"],[0,5,"siege"],[1,0,"town-center"],[1,6,"tower"]]:
  menu.manual_section=row[0];menu.manual_index=row[1];menu._show_page("manual")
  ok=(await shot(menu,"native-catalogue-"+row[2])) and ok
  print("CATALOGUE ",menu.manual_preview.model_kind," active=",menu.manual_preview.active," battle_exists=",is_instance_valid(menu.match_node))
 print(JSON.stringify({"build":menu.Rules.BUILD_ID,"rendered":DisplayServer.get_name()!="headless","scope":"Actual in-game model catalogue interface from exact exported product; original shared unit/building models; not a battlefield or combat screenshot."}));menu.queue_free();quit(0 if ok else 1)
