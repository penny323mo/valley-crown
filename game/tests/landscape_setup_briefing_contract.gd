extends SceneTree
var shell
var checks=[]
var records=[]
func _initialize():call_deferred("run")
func check(name,ok):
 checks.append({"name":name,"passed":bool(ok)})
 if not ok:push_error(name)
func settle():
 for i in 5:await process_frame
func one_touch(pos,index=5):
 for down in [true,false]:
  var e=InputEventScreenTouch.new();e.index=index;e.position=pos;e.pressed=down;root.push_input(e);await process_frame
 await settle()
func tap(name):
 var row=shell.buttons.get_node_or_null(name)
 if not is_instance_valid(row):push_error("missing button "+name);return
 await one_touch(row.get_global_rect().get_center())
func geo(x):
 var r=x.get_global_rect()
 return [r.position.x,r.position.y,r.size.x,r.size.y]
func measure(size,selection,label):
 var sc=shell.scroll.get_global_rect()
 var mode=shell.mode_title
 var map_line=shell.short_setup_map
 var goal=shell.short_setup_goal
 var action_rects=[]
 for b in shell.buttons.get_children():action_rects.append(b.get_global_rect())
 check("all actual touch actions fully accessible "+label,action_rects.size()>=3 and action_rects.all(func(r):return r.size.y>=44 and root.get_visible_rect().encloses(r) and not r.intersects(sc)))
 for i in range(action_rects.size()):
  for j in range(i+1,action_rects.size()):
   if action_rects[i].intersects(action_rects[j]):check("actions never overlap "+label,false)
 check("actual title mode map and goal visible at first frame "+label,shell.setup_split_active and shell.heading.visible and mode.visible and map_line.visible and goal.visible and [shell.heading,mode,map_line,goal].all(func(r):return sc.encloses(r.get_global_rect())))
 check("actual displayed selected map and exact win conditions "+label,shell.selected_layout==selection and map_line.text==("戰場："+shell.BattlefieldLayout.title(selection)) and goal.text==("勝利："+shell.BattleSelection.briefing_sections(shell.selected_mode,shell.selected_victory_mode,shell.selected_difficulty).win))
 check("action rail and prose carry real bounded sizes "+label,sc.size.y>=size.y-64 and action_rects[0].size.x>=198 and action_rects[0].size.y<=54)
 records.append({"size":[size.x,size.y],"goal":goal.text,"map":map_line.text,"difficulty":shell.selected_difficulty,"clip":geo(shell.scroll),"launch":geo(shell.buttons.get_node("LaunchMatchButton"))})
func journey(size):
 root.size=size;shell=load("res://main_menu.tscn").instantiate();root.add_child(shell);await settle()
 for key in ["StartMatchButton","BattleGroup0","ChooseBattle_standard"]:await tap(key)
 check("ordinary setup reached without starting "+str(size),shell.page=="setup" and not is_instance_valid(shell.match_node))
 measure(size,"valley","classic "+str(size))
 await tap("ChooseDifficultyButton")
 await tap("DifficultyEasyButton")
 check("genuine difficulty touch changes only selected difficulty "+str(size),shell.selected_difficulty=="easy" and shell.selected_layout=="valley" and shell.page=="setup")
 await tap("ChooseLayoutButton")
 await tap("LayoutRiverCrossingsButton")
 check("genuine map touch returns to setup "+str(size),shell.selected_layout=="river_crossings" and shell.selected_difficulty=="easy" and shell.page=="setup")
 measure(size,"river_crossings","river "+str(size))
 var touch_before=geo(shell.buttons.get_node("LaunchMatchButton"))
 root.size=Vector2i(390,844);await settle()
 check("rotation preserves setup selection without starting "+str(size),shell.selected_layout=="river_crossings" and shell.selected_difficulty=="easy" and shell.page=="setup" and not is_instance_valid(shell.match_node))
 check("portrait untouched restores prior full stack geometry "+str(size),not shell.setup_split_active and not shell.short_setup_map.visible and not shell.short_setup_goal.visible and shell.scroll.size==Vector2(298,282) and shell.buttons.get_node("LaunchMatchButton").size==Vector2(234,54))
 root.size=size;await settle()
 check("rotation back restores same safe launch target "+str(size),geo(shell.buttons.get_node("LaunchMatchButton"))==touch_before and shell.selected_layout=="river_crossings" and shell.selected_difficulty=="easy")
 await tap("LaunchMatchButton")
 check("real Launch starts same mode selected map and easy AI "+str(size),is_instance_valid(shell.match_node) and shell.match_node.layout_id=="river_crossings" and shell.match_node.ai_difficulty=="easy" and shell.match_node.skirmish_mode=="standard")
 shell.queue_free();await settle()
func real_long_goal():
 var size=Vector2i(640,360);root.size=size
 shell=load("res://main_menu.tscn").instantiate();root.add_child(shell);await settle()
 for key in ["StartMatchButton","BattleGroup3","ChooseBattle_depot"]:await tap(key)
 check("ordinary Frontline Depot enters setup without starting",shell.page=="setup" and not is_instance_valid(shell.match_node) and shell.selected_mode=="depot")
 check("long existing resource-delivery goal entirely visible without scrolling",shell.scroll.get_global_rect().encloses(shell.short_setup_goal.get_global_rect()) and shell.short_setup_goal.text.contains("木材120及糧食80") and shell.short_setup_goal.text.contains("交易及退款不計"))
 check("no duplicated map label in landscape details",not shell.description.text.contains(shell.short_setup_map.text))
 await tap("LaunchMatchButton")
 check("actual normal Launch retains Frontline Depot rules",is_instance_valid(shell.match_node) and shell.match_node.skirmish_mode=="depot")
 shell.queue_free();await settle()
func run():
 for size in [Vector2i(640,360),Vector2i(844,390)]:await journey(size)
 await real_long_goal()
 var unsuccessful=checks.filter(func(x):return not x.passed)
 print(JSON.stringify({"checks":checks,"failed":unsuccessful.size(),"scope":"Actual native touch setup, layout/difficulty rotation and ordinary launch; confirms existing long objective, geometry and portrait parity. No physical iPhone or browser visual proof.","suite":"landscape_setup_briefing_contract"}))
 quit(0 if unsuccessful.is_empty() else 1)
