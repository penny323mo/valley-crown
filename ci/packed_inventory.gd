# Native packed-resource inventory. External harness must remain outside the pack.
extends SceneTree
var files=[]
func walk(path):
 var d=DirAccess.open(path)
 if d==null:return
 d.include_hidden=true;d.include_navigational=false;d.list_dir_begin()
 var entry=d.get_next()
 while not entry.is_empty():
  var next=path.path_join(entry)
  if d.current_is_dir():walk(next)
  else:files.append(next)
  entry=d.get_next()
 d.list_dir_end()
func _initialize():
 walk("res://");files.sort();var forbidden=[]
 for f in files:
  if f.begins_with("res://tests/") or f.begins_with("res://art/") or f.begins_with("res://reports/") or f.begins_with("res://tools/") or f.begins_with("res://screenshots/") or f.begins_with("res://assets/models/") or f.ends_with(".blend") or f.ends_with(".glb") or f.ends_with(".gltf"):forbidden.append(f)
 var required=true
 for p in ["res://main.tscn","res://scripts/game.gd","res://scripts/rules.gd","res://scripts/construction_visual.gd","res://scripts/observed_occlusion.gd","res://assets/fonts/ui_tc.otf","res://assets/mature/models/villager_action.scn","res://assets/mature/models/spearman_action.scn","res://assets/mature/models/archer_action.scn","res://assets/mature/models/scout_action.scn","res://assets/mature/models/town_center.scn","res://assets/mature/models/house.scn","res://assets/mature/models/barracks.scn","res://assets/mature/models/range.scn","res://assets/mature/models/storehouse.scn","res://assets/mature/shaders/observed_occlusion.gdshader","res://assets/mature/shaders/observed_visibility_mask.gdshader"]:required=required and ResourceLoader.exists(p)
 var ok=forbidden.is_empty() and required;FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"passed":ok,"forbidden":forbidden,"required_resources_present":required,"resource_count":files.size(),"files":files},"  "));print("PACKED_INVENTORY ",ok," count=",files.size());quit(0 if ok else 1)
