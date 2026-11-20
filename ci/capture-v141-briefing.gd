extends SceneTree
var shell
var expected=""
var role=""
var out=""
var size=Vector2i(640,360)
var checks=[]
var images={}
func _initialize():call_deferred("run")
func check(name,ok):
 checks.append({"name":name,"passed":bool(ok)})
 if not ok:push_error(name)
func settle():
 for i in 5:await process_frame
func touch(name):
 var b=shell.buttons.get_node_or_null(name)
 if not is_instance_valid(b):check("button "+name,false);return
 var center=b.get_global_rect().get_center()
 check("normal touch visible "+name,b.is_visible_in_tree() and root.get_visible_rect().has_point(center))
 for down in [true,false]:
  var e=InputEventScreenTouch.new();e.index=44;e.position=center;e.pressed=down;root.push_input(e);await process_frame
 await settle()
func frame(tag):
 if out.is_empty():return
 RenderingServer.render_loop_enabled=true
 await settle()
 await RenderingServer.frame_post_draw
 var im=root.get_texture().get_image()
 var p=out+"/"+tag+".png"
 DirAccess.make_dir_recursive_absolute(out)
 check("real Godot setup image "+tag,im.save_png(p)==OK and im.get_size()==size)
 images[tag]={"size":[size.x,size.y],"sha256":FileAccess.get_sha256(p)}
 RenderingServer.render_loop_enabled=false
func run():
 var args=OS.get_cmdline_user_args()
 assert(args.size()==5)
 size=Vector2i(int(args[1]),int(args[2]));expected=args[3];role=args[4];root.size=size
 if DisplayServer.get_name()!="headless":
  out=args[0];RenderingServer.render_loop_enabled=false
 shell=load("res://main_menu.tscn").instantiate();root.add_child(shell);await settle()
 for b in ["StartMatchButton","BattleGroup0","ChooseBattle_standard","ChooseLayoutButton","LayoutRiverCrossingsButton"]:await touch(b)
 check("real chosen river setup, no match starts",shell.page=="setup" and shell.selected_layout=="river_crossings" and not is_instance_valid(shell.match_node))
 await frame("river-briefing")
 for b in ["ChooseBattleButton","BattleGroup3","ChooseBattle_depot"]:await touch(b)
 check("real long objective setup, no match starts",shell.page=="setup" and shell.selected_mode=="depot" and not is_instance_valid(shell.match_node))
 var clip=shell.scroll.get_global_rect()
 var goal_visible=false
 if role=="candidate":
  var goal=shell.get("short_setup_goal")
  goal_visible=is_instance_valid(goal) and goal.is_visible_in_tree() and clip.encloses(goal.get_global_rect()) and goal.text.contains("木材120")
  check("entire real long depot objective visible first frame",goal_visible)
 else:
  check("old first-frame real long objective is clipped",not clip.encloses(shell.description.get_global_rect()))
 await frame("long-goal-briefing")
 await touch("LaunchMatchButton")
 check("real Launch starts the selected mode exact build",is_instance_valid(shell.match_node) and shell.match_node.skirmish_mode=="depot" and shell.match_node._snapshot().build==expected)
 var f=checks.filter(func(x):return not x.passed)
 var report={"checks":checks,"failed":f.size(),"images":images,"size":[size.x,size.y],"role":role,"build":expected,"long_goal_visible":goal_visible,"scope":"Exact native game layout and ordinary native Godot ScreenTouch menu routing, not a physical iPhone."}
 print(JSON.stringify(report))
 if not out.is_empty():
  var output=FileAccess.open(out+"/report.json",FileAccess.WRITE)
  output.store_string(JSON.stringify(report))
 shell.queue_free();quit(0 if f.is_empty() else 1)
