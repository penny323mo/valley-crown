extends RefCounted
## Authored fixed map terrain. No hidden observation or entities.
const Rules=preload("res://scripts/rules.gd")
const ID="river_crossings"
const BANK_Z_MIN=-3
const BANK_Z_MAX=3
const BRIDGE_X_MIN=-18
const BRIDGE_X_MAX=-8
const FORD_X_MIN=8
const FORD_X_MAX=18
enum {DRY,WATER,BRIDGE,FORD}

static func surface_at(id:String,cell:Vector2i) -> int:
 if id!=ID:return DRY
 var x=cell.x-int(Rules.MAP_HALF)
 var z=cell.y-int(Rules.MAP_HALF)
 if z<BANK_Z_MIN or z>=BANK_Z_MAX:return DRY
 if x>=BRIDGE_X_MIN and x<BRIDGE_X_MAX:return BRIDGE
 if x>=FORD_X_MIN and x<FORD_X_MAX:return FORD
 return WATER

static func blocked(id:String) -> Dictionary:
 var cells={}
 if id==ID:
  for y in range(BANK_Z_MIN+int(Rules.MAP_HALF),BANK_Z_MAX+int(Rules.MAP_HALF)):
   for x in range(Rules.MAP_BORDER,Rules.MAP_LAST_PLAYABLE+1):
    var cell=Vector2i(x,y)
    if surface_at(id,cell)==WATER:cells[cell]=true
 cells.make_read_only()
 return cells

## Surface-aware public worn tracks. Existing old maps retain their old mask.
static func corridor_mask() -> Dictionary:
 var cells={}
 for side in [1,-1]:
  _trail(cells,Vector2(-25.0,20.0)*side,Vector2(-13.0,5.0)*side)
  # Evenly shared east/west crossing alternatives, on land only.
  _trail(cells,Vector2(-13.0,5.0)*side,Vector2(13.0,5.0)*side)
  for x in [-13.0,13.0]:_trail(cells,Vector2(x,5.0)*side,Vector2(x,3.05)*side)
 cells.make_read_only()
 return cells
static func _trail(cells:Dictionary,a:Vector2,b:Vector2):
 for i in range(81):
  var p=a.lerp(b,float(i)/80.0)
  for offset in [-0.48,0.0,0.48]:
   var c=Vector2i(floori(p.x+Rules.MAP_HALF),floori(p.y+offset+Rules.MAP_HALF))
   if surface_at(ID,c)==DRY:cells[c]=true
