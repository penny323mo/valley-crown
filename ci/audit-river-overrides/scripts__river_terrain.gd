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
