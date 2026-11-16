extends SceneTree
const OUT="/tmp/capture/"
func _initialize():call_deferred("run")
func shot(g,name):
 g._publish_faction_views();g._update_vision();g._update_visuals(0);g._update_hud();g._layout_ui();g._camera_update();g._refresh_army_roster()
 await process_frame
 if g.compact_menu.visible:g.shortcut_scroll.ensure_control_visible(g.army_roster_buttons.spearman.recruit)
 await process_frame
 await RenderingServer.frame_post_draw
 var im=root.get_texture().get_image();var err=im.save_png(OUT+name+".png")
 print("CAPTURE ",name," ",im.get_width(),"x",im.get_height()," ",err)
 return err==OK
func run():
 root.size=Vector2i(360,640)
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="fortress";root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false
 g._test_reset([{"food":2000,"wood":2000,"stone":1000,"iron":1000},{"food":150,"wood":200,"stone":100,"iron":0}]);g.set_process(false);await process_frame
 g.paused=false;g.application_focused=true;g.application_suspended=false;g._skip_tutorial()
 var first=g._first(0,"barracks");var second=g._spawn("barracks",0,Vector3(-3.5,0,24.5));g._update_vision();g._update_hud()
 g.compact_menu.show();g._set_shortcut_category("army");g._refresh_army_roster()
 # Controlled remaining-time fixture, all existing orders paid by normal authority.
 g._execute({"type":"train","team":0,"building":first.id,"kind":"spearman"})
 g._execute({"type":"train","team":0,"building":second.id,"kind":"spearman"})
 g._execute({"type":"train","team":0,"building":second.id,"kind":"spearman"})
 first.queue[0].remaining_ticks=300
 second.queue[0].remaining_ticks=1;second.queue[1].remaining_ticks=20
 g._publish_faction_views();g._refresh_army_roster()
 var plan=g._army_recruitment_plan("spearman");var before=g.economy.bank_milli(0).duplicate()
 var ok=await shot(g,"native-shortest-time-reinforcement-menu")
 g.army_roster_buttons.spearman.recruit.pressed.emit()
 var queued=g.commands.size()==3 and g.commands.all(func(c):return c.type=="train" and c.kind=="spearman")
 while not g.commands.is_empty():g._execute(g.commands.pop_front())
 var paid=g.economy.bank_milli(0).food==before.food-150000 and g.economy.bank_milli(0).wood==before.wood-60000
 var split=first.queue.size()==2 and second.queue.size()==4
 var routed=plan.orders.size()==3 and plan.orders[0].building==second.id and plan.orders[1].building==first.id and plan.orders[2].building==second.id
 g.compact_menu.hide();g._publish_faction_views();g._select([second.id]);g.camera_focus=second.pos
 ok=(await shot(g,"native-faster-barracks-receives-two-reinforcements")) and ok
 print(JSON.stringify({"build":g.Rules.BUILD_ID,"scope":"Controlled fortress, funded second barracks, three normally paid initial orders, remaining timers set to 300 versus 1+20 ticks; actual menu button and ordinary training payments. No gifted completed troops, natural-match or phone acceptance","plan_count":plan.count,"queued":queued,"paid_exactly":paid,"queues_two_plus_four":split,"shortest_time_routing":routed,"food_milli":g.economy.bank_milli(0).food,"wood_milli":g.economy.bank_milli(0).wood}))
 ok=ok and queued and paid and split and routed and plan.count==3
 g.queue_free();quit(0 if ok else 1)
