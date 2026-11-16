extends RefCounted
## Advisory crowding from current owned observations and this turn's orders.
## Does not reserve nodes, inspect hidden units, or alter route/cargo authority.
static func assignments(records: Dictionary, commands: Array, team: int, exclude: int) -> Dictionary:
 var result={}
 for w in records.values():
  if w.get("id",-1)==exclude or not w.get("owned",false) or not w.get("alive",false) or w.get("remembered",true) or w.get("team",-1)!=team or w.get("kind","")!="villager":continue
  if w.get("state","")=="gather":result[w.id]=w.get("target",-1)
  elif w.get("state","")=="deliver":result[w.id]=w.get("resource_target",-1)
 for c in commands:
  if c.get("team",-1)==team and c.get("type","")=="build":
   result.erase(c.get("builder",-1))
   continue
  if c.get("team",-1)!=team or c.get("type","") not in ["order","stop","defend","advance","patrol"]:continue
  for id in c.get("ids",[]):
   var w=records.get(id,{})
   if id==exclude or not w.get("owned",false) or not w.get("alive",false) or w.get("remembered",true) or w.get("team",-1)!=team or w.get("kind","")!="villager":continue
   result[id]=c.get("target",-1) if c.type=="order" else -1
 var loads={}
 for id in result.values():
  if id>=0:loads[id]=loads.get(id,0)+1
 return loads
static func score(origin:Vector3,node:Dictionary,loads:Dictionary)->float:
 # A bounded eight-unit maximum discourages local congestion without sending
 # workers across the map merely because a distant node has zero assignments.
 return origin.distance_to(node.pos)+2.0*mini(4,loads.get(node.id,0))
