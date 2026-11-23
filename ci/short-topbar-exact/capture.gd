extends SceneTree
# Original 480x270 Godot viewport; real GUI touch routing in normal Standard.
const Rules=preload("res://scripts/rules.gd")
var g
var m
var role:String
var out:String
var visual:bool
var checks:Array=[]
var reports:Dictionary={}
var actions:Array=[]
func _initialize():call_deferred("run")
func settle(n:int=5):
 for i in n:await process_frame
func ck(label:String,ok:bool)->bool:
 checks.append({"label":label,"pass":ok})
 if not ok:push_error(label)
 return ok
func point(p:Vector2,down:bool):
 var e=InputEventScreenTouch.new()
 e.index=22;e.position=p;e.pressed=down
 root.push_input(e,true)
func rect(r:Rect2)->Array:return [r.position.x,r.position.y,r.size.x,r.size.y]
func act(label:String,b:Control,clip:Rect2=Rect2(),settling:int=5):
 if not ck("valid real touch "+label,is_instance_valid(b) and b.is_visible_in_tree() and not b.disabled):
  return false
 var r=b.get_global_rect().intersection(root.get_visible_rect())
 if clip.has_area():r=r.intersection(clip)
 if not ck("touch inside screen "+label,r.has_area() and root.get_visible_rect().encloses(r)):return false
 var p=r.get_center()
 actions.append({"name":label,"point":[p.x,p.y],"visible_rect":rect(r)})
 point(p,true);await settle(1)
 point(p,false)
 if settling>0:await settle(settling)
 return true
func state()->Dictionary:
 var own=g.faction_views[0].records().values().filter(func(r):return r.get("owned",false) and r.get("alive",false))
 own.sort_custom(func(a,b):return a.id<b.id)
 var actors=own.map(func(r):return [r.id,r.kind,str(r.pos),r.get("hp",-1),r.get("built",false)])
 return {"bank":g.economy.bank_milli(0),"owned":actors,"camera":str(g.camera.global_transform),
  "focus":str(g.camera_focus),"zoom":g.camera_zoom,"sequence":g.command_sequence,"queue":g.commands.duplicate(true),
  "tick":g.tick_count,"selected":g.selected.duplicate(),"menu":g.compact_menu.visible,"paused":g.paused,"tab":g.shortcut_category}
func save_frame(label:String):
 var menu=g.compact_menu_button
 var idle=g.compact_top_line.get_node_or_null("InlineIdleWorker")
 var state_before=state()
 reports[label]={"state":state_before,"geometry":{
  "hud":rect(g.hud_top.get_global_rect()),"menu":rect(menu.get_global_rect()),
  "menu_visible":rect(menu.get_global_rect().intersection(root.get_visible_rect())),"menu_label":menu.text,
  "pause":rect(g.pause_button.get_global_rect()),"pause_label":g.pause_button.text,
  "idle":rect(idle.get_global_rect()) if is_instance_valid(idle) and idle.is_visible_in_tree() else [],
  "tutorial":rect(g.tutorial_entry.get_global_rect()) if g.tutorial_entry.is_visible_in_tree() else []}
 }
 if not visual:return true
 if not ck("native llvmpipe "+label,DisplayServer.get_name()!="headless" and RenderingServer.get_current_rendering_method()=="gl_compatibility" and "llvmpipe" in RenderingServer.get_video_adapter_name().to_lower()):
  return false
 var draws=[0];var marker=func():draws[0]+=1
 RenderingServer.frame_post_draw.connect(marker);RenderingServer.render_loop_enabled=true
 var start=Time.get_ticks_msec()
 while draws[0]<3 and Time.get_ticks_msec()-start<30000:await process_frame
 RenderingServer.render_loop_enabled=false;RenderingServer.frame_post_draw.disconnect(marker)
 if not ck("three draws with unchanged state "+label,draws[0]>=3 and state()==state_before):return false
 var im=root.get_texture().get_image()
 if not ck("original size "+label,im!=null and not im.is_empty() and im.get_size()==Vector2i(480,270)):
  return false
 var colors={}
 for ix in range(0,480,16):
  for iy in range(0,270,16):colors[im.get_pixel(ix,iy).to_rgba32()]=true
 var path=out+"/"+label+".png"
 if not ck("new genuine PNG "+label,colors.size()>30 and not FileAccess.file_exists(path) and im.save_png(path)==OK):return false
 reports[label].png_sha256=FileAccess.get_sha256(path)
 return true
func result():
 var f=FileAccess.open(out+"/report.json",FileAccess.WRITE)
 if f!=null:
  f.store_string(JSON.stringify({"build":Rules.BUILD_ID,"role":role,"viewport":[root.size.x,root.size.y],
   "engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),
   "game_sha":FileAccess.get_sha256("res://scripts/game.gd"),"rules_sha":FileAccess.get_sha256("res://scripts/rules.gd"),
   "manifest_sha":FileAccess.get_sha256("res://reports/build-manifest.json"),"checks":checks,"reports":reports,"actions":actions},"  "))
 quit(1 if checks.any(func(c):return not c.pass) or f==null else 0)
func launch():
 m=load("res://main_menu.tscn").instantiate()
 root.add_child(m);await settle(8)
 for n in ["StartMatchButton","BattleGroup0","ChooseBattle_standard","LaunchMatchButton"]:
  var is_launch=n=="LaunchMatchButton"
  if not await act(n,m.buttons.get_node_or_null(n),Rect2(),0 if is_launch else 5):return false
 for i in 120:
  await process_frame
  if is_instance_valid(m.match_node):
   g=m.match_node;g.set_process(false);break
 if not ck("ordinary Standard match starts at natural initial tick",is_instance_valid(g) and g.skirmish_mode=="standard" and not g.test_mode and g.tick_count==0):
  return false
 await settle()
 return true
func run():
 var args=OS.get_cmdline_user_args()
 role=args[0];out=args[1];visual=args[2]=="RENDERED"
 root.size=Vector2i(480,270)
 if not await launch():result();return
 var menu=g.compact_menu_button;var pause=g.pause_button;var reserve=g.idle_worker_button
 var hud=g.hud_top;var inline=g.compact_top_line.get_node_or_null("InlineIdleWorker")
 var before=state()
 var expected_worker=reserve.get_meta("idle_target",-1)
 if role=="candidate":
  ck("full independent menu, pause and idle",is_instance_valid(inline) and inline.is_visible_in_tree() and inline.size==Vector2(46,46)
    and menu.text=="選單" and root.get_visible_rect().encloses(hud.get_global_rect()) and root.get_visible_rect().encloses(menu.get_global_rect())
    and not inline.get_global_rect().intersects(menu.get_global_rect()) and not inline.get_global_rect().intersects(pause.get_global_rect()))
 else:
  ck("old Menu caption clipped, no direct Idle",inline==null and menu.text=="閒置" and
    menu.get_global_rect().intersection(root.get_visible_rect()).size==Vector2(15,46) and not root.get_visible_rect().encloses(hud.get_global_rect()))
 if not await save_frame("opening"):result();return
 if not await act("Menu",menu):result();return
 ck("opening tap shows Menu but does not select/order",g.compact_menu.visible and g.selected==before.selected and g.command_sequence==before.sequence and g.compact_menu_button.text=="收起")
 if not await save_frame("menu-open"):result();return
 if role=="baseline":
  if not await act("drawer Idle",reserve,g.shortcut_scroll.get_global_rect()):result();return
 else:
  # Independent one-tap proof starts from a fresh ordinary opening. The
  # comparison model does not fake HUD refreshes after opening its Menu.
  m.free();await settle()
  if not await launch():result();return
  ck("separate fresh direct Idle matches initial opening",state()==before)
  inline=g.compact_top_line.get_node("InlineIdleWorker")
  pause=g.pause_button
  if not await act("top-row Idle",inline):result();return
 var worker=g.faction_views[0].get_record(expected_worker)
 ck("exact idle worker selected and focused without order/spend",worker.get("kind","")=="villager" and g.selected==[expected_worker]
   and g.camera_focus==worker.pos and not g.compact_menu.visible and g.command_sequence==before.sequence and g.commands==before.queue and g.economy.bank_milli(0)==before.bank)
 if not await save_frame("worker-focused"):result();return
 if not await act("Pause",pause):result();return
 ck("Pause remains reachable through native touch and preserves selected worker",g.paused and g.selected==[expected_worker] and g.command_sequence==before.sequence)
 if not await save_frame("paused"):result();return
 result()
