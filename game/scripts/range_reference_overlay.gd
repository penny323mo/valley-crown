extends Control
## Presentation only. The outline marks distance to a target's edge, not its
## centre and not a guarantee of firing. Never reads enemy entities or terrain.
const Rules=preload("res://scripts/rules.gd")
const SEGMENTS=64
var game

static func observed_profile(records: Dictionary,selection: Array) -> Dictionary:
 if selection.size()!=1:return {}
 var r=records.get(selection[0],{})
 if not r.get("owned",false) or not r.get("alive",false) or r.get("team",-1)!=0 or r.get("remembered",false):return {}
 if r.get("kind","") not in ["archer","tower"] or not r.get("built",false) or r.get("garrisoned",false):return {}
 return {"position":r.pos,"radius":float(Rules.RANGE[r.kind]),"preview":false}

static func cell_visible(p: Vector3,visible) -> bool:
 var x=floori(p.x+Rules.MAP_HALF);var y=floori(p.z+Rules.MAP_HALF)
 return visible.size()==Rules.MAP_SIZE*Rules.MAP_SIZE and x>=0 and y>=0 and x<Rules.MAP_SIZE and y<Rules.MAP_SIZE and visible[y*Rules.MAP_SIZE+x]!=0

static func visible_segments(profile: Dictionary,visible) -> Array:
 var result=[]
 if profile.is_empty() or not profile.position.is_finite():return result
 if not cell_visible(profile.position,visible):return result
 var p:Vector3=profile.position;var radius:float=profile.radius
 if not p.is_finite() or radius<=0 or radius>10:return result
 for index in SEGMENTS:
  var a=p+Vector3(cos(index*TAU/SEGMENTS),0,sin(index*TAU/SEGMENTS))*radius
  var b=p+Vector3(cos((index+1)*TAU/SEGMENTS),0,sin((index+1)*TAU/SEGMENTS))*radius
  # Conservative supercover: every cell in the tiny segment AABB must be
  # currently visible. No outline across unexplored OR remembered-only cells.
  var allowed=true
  for y in range(floori(minf(a.z,b.z)+Rules.MAP_HALF),floori(maxf(a.z,b.z)+Rules.MAP_HALF)+1):
   for x in range(floori(minf(a.x,b.x)+Rules.MAP_HALF),floori(maxf(a.x,b.x)+Rules.MAP_HALF)+1):
    if x<0 or y<0 or x>=Rules.MAP_SIZE or y>=Rules.MAP_SIZE or visible[y*Rules.MAP_SIZE+x]==0:allowed=false
  if allowed:result.append([Vector3(a.x,.16,a.z),Vector3(b.x,.16,b.z)])
 return result

func profile() -> Dictionary:
 if not is_instance_valid(game) or game.game_over or game.paused or not game.application_focused or game.application_suspended:return {}
 if not game.build_mode.is_empty():
  if game.build_mode!="tower" or not game.placement_ok or not is_instance_valid(game.ghost) or not game.ghost.is_visible_in_tree():return {}
  return {"position":game.ghost.global_position,"radius":float(Rules.RANGE.tower),"preview":true}
 if game.touch_command or game.box_select_mode:return {}
 return observed_profile(game.faction_views[0].records(),game.selected)

func _process(_delta):queue_redraw()
func _draw():
 if not is_instance_valid(game) or not is_instance_valid(game.camera):return
 var current=profile()
 for segment in visible_segments(current,game.visible_cells[0]):
  if game.camera.is_position_behind(segment[0]) or game.camera.is_position_behind(segment[1]):continue
  var a=game.camera.unproject_position(segment[0]);var b=game.camera.unproject_position(segment[1])
  draw_line(a,b,Color(.1,.85,.95,.85),2,true)
