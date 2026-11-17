extends SceneTree
const Rules=preload("res://scripts/rules.gd")
const Overlay=preload("res://scripts/range_reference_overlay.gd")
var menu
var g
var o
var out=""
var checks=[]
var metadata_only=false
var report={"captures":[],"scope":"Controlled actual game fixture with explicitly spawned own archer and completed tower; NOT naturally trained/built battle progression. Ordinary valid unpaid tower preview. Natural faction visibility, no reveal-all or fog mask edits. No physical phone/browser validation."}
func _initialize():call_deferred("run")
func check(n,b):checks.append({"name":n,"pass":bool(b)});return bool(b)
func settle():await process_frame;await process_frame
func shot(name):
 g._camera_update();g._refresh_fog();g._update_visuals(0);g._update_hud();o.queue_redraw();await settle()
 var profile=o.profile();var segments=Overlay.visible_segments(profile,g.visible_cells[0])
 check(name+" visible reference segments",segments.size()>0)
 var row={"name":name,"profile":profile,"visible_segments":segments.size(),"tick":g.tick_count,"bank":g.economy.bank_milli(0),"selected":g.selected.duplicate(),"camera":str(g.camera_focus),"zoom":g.camera_zoom,"selection_detail":g.selection_detail.text,"placement_ok":g.placement_ok,"metadata_only":metadata_only}
 if not metadata_only:
  await RenderingServer.frame_post_draw
  var p=out+"/"+name+".png";check(name+" PNG",root.get_texture().get_image().save_png(p)==OK);row.file=p;row.sha256=FileAccess.get_sha256(p)
 report.captures.append(row)
func finish():
 report.checks=checks;report.failed=checks.filter(func(x):return not x.pass).size()
 var f=FileAccess.open(out+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close();print(JSON.stringify({"failed":report.failed,"checks":checks.size()}));quit(1 if report.failed else 0)
func run():
 var args=OS.get_cmdline_user_args();out=args[0] if args.size()>0 else "/tmp/v92-range-capture"
 if DirAccess.dir_exists_absolute(out):quit(2);return
 DirAccess.make_dir_recursive_absolute(out);metadata_only=DisplayServer.get_name()=="headless" or "--metadata-only" in args
 report.build=Rules.BUILD_ID;report.driver_sha256=FileAccess.get_sha256(get_script().resource_path)
 for p in ["game","range_reference_overlay","rules"]:report[p+"_sha256"]=FileAccess.get_sha256("res://scripts/"+p+".gd")
 root.size=Vector2i(960,540);menu=load("res://main_menu.tscn").instantiate();root.add_child(menu);await settle()
 for id in ["StartMatchButton","BattleGroup0","ChooseBattle_standard","LaunchMatchButton"]:
  var b=menu.find_child(id,true,false)
  if not check(id,b is Button and b.is_visible_in_tree()):finish();return
  b.pressed.emit();await settle()
 g=menu.match_node;g.set_process(false);g.ai_enabled=false;report.ai_disabled=true
 var worker=g._first(0,"villager")
 var archer=g._spawn("archer",0,worker.pos+Vector3(2,0,2));g._update_vision();g._select([archer.id])
 g.camera_zoom=20;g.camera_focus=archer.pos;g._camera_update();g._layout_ui();o=g.ui.get_node("RangeReferenceOverlay")
 check("own archer profile",o.profile().get("radius",0)==Rules.RANGE.archer)
 await shot("01-controlled-own-archer")
 var tower=g._spawn("tower",0,archer.pos+Vector3(4,0,0));g._update_vision();g._select([tower.id]);g.camera_focus=tower.pos
 check("own completed tower profile",o.profile().get("radius",0)==Rules.RANGE.tower)
 await shot("02-controlled-own-tower")
 var bank=g.economy.bank_milli(0).duplicate(true)
 g._select([worker.id]);g._start_build("tower")
 var found=false
 for z in range(-12,13):
  for x in range(-12,13):
   if found:break
   g.pointer_world=g._first(0,"town_center").pos+Vector3(x,0,z);g._update_ghost()
   if g.placement_ok and Overlay.cell_visible(g.ghost.global_position,g.visible_cells[0]):found=true
 if not check("ordinary legal preview",found and o.profile().get("preview",false)):finish();return
 g.camera_focus=g.ghost.global_position
 await shot("03-legal-unpaid-tower-preview")
 check("preview not charged",g.economy.bank_milli(0)==bank)
 check("passive overlay",o.mouse_filter==Control.MOUSE_FILTER_IGNORE)
 finish()
