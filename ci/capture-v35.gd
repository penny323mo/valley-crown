extends SceneTree
const OUT="/tmp/capture/"
func _initialize():call_deferred("run")
func shot(g,name,follow=true):
 if follow and not g.selected.is_empty():g.camera_focus=g._get_entity(g.selected[0]).pos
 g._update_vision(false);g._publish_faction_views();g._update_visuals(0);g._update_hud();g._layout_ui();g._camera_update()
 await process_frame
 await process_frame
 if DisplayServer.get_name()=="headless":return true
 await RenderingServer.frame_post_draw
 var im=root.get_texture().get_image();var err=im.save_png(OUT+name+".png")
 print("CAPTURE ",name," ",im.get_width(),"x",im.get_height()," ",err)
 return err==OK
func run():
 root.size=Vector2i(640,360)
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.set_process(false);g.ai_enabled=false
 await process_frame
 g.paused=false;g.application_focused=true;g.application_suspended=false;g._skip_tutorial();g.camera_zoom=15
 var worker=g._first(0,"villager");var berry=g._nearest_resource(worker.pos,"food",0);g._order(worker,"gather",berry.id)
 var elapsed=0
 for i in 1800:
  g._tick(.05);elapsed+=1
  if g._cargo_amount(worker)>=5000:break
 var cargo=g._cargo_amount(worker);var earned=cargo>0 and g._cargo_type(worker)=="food";var bank=g.economy.bank_milli(0).food
 g._update_vision(false);g._publish_faction_views();g._select([worker.id]);g.compact_menu.show();g._set_shortcut_category("economy");g._refresh_idle_dispatch_buttons();g._layout_ui()
 await process_frame
 await process_frame
 g.shortcut_scroll.ensure_control_visible(g.workforce_reassign_buttons.wood)
 var ok=await shot(g,"native-selected-workforce-reassign-menu")
 g._reassign_selected_workforce("wood")
 var queued=g.commands.size()==1 and g.commands[0].get("work_reassign","")=="wood"
 g._tick(.05);elapsed+=1
 var preserved=g._cargo_amount(worker)>=cargo and g._cargo_type(worker)=="food" and worker.state=="deliver" and worker.gather_type=="wood"
 ok=(await shot(g,"native-reassigned-worker-keeps-food-cargo")) and ok
 var wood=false
 for i in 2400:
  g._tick(.05);elapsed+=1
  if g._cargo_amount(worker)>=1000 and g._cargo_type(worker)=="wood":wood=true;break
 var deposited=g.economy.bank_milli(0).food>=bank+cargo
 ok=(await shot(g,"native-original-food-deposited-now-gathering-wood")) and ok
 var proof={"build":g.Rules.BUILD_ID,"scope":"Controlled single worker ordinary food gathering, real economy-menu reassignment and native delivery/wood harvest. No saved files, phone or natural-match acceptance.","earned_food_cargo":earned,"food_cargo_milli":cargo,"ordinary_order_queued":queued,"cargo_preserved":preserved,"food_deposited":deposited,"now_gathering_wood":wood,"food_bank_before":bank,"food_bank_after":g.economy.bank_milli(0).food,"ledger_conserved":g.economy.audit().ok,"ticks":elapsed,"rendered":DisplayServer.get_name()!="headless"}
 print(JSON.stringify(proof));g.queue_free();quit(0 if ok and earned and queued and preserved and deposited and wood and proof.ledger_conserved else 1)
