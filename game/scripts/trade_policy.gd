extends RefCounted
## Fixed lossy recipes, not dynamic prices or a delivery source.
const TICKS=300
const RECIPES={
 "trade_wood_food":{"from":"wood","to":"food","input":100,"output":60},
 "trade_food_wood":{"from":"food","to":"wood","input":100,"output":60},
 "trade_food_iron":{"from":"food","to":"iron","input":100,"output":30},
 "trade_food_stone":{"from":"food","to":"stone","input":100,"output":40}}
static func recipe(from_resource,to_resource)->Dictionary:
 for key in RECIPES:
  var row=RECIPES[key]
  if row.from==from_resource and row.to==to_resource:return row.duplicate(true)
 return {}
static func kind(from_resource,to_resource)->String:
 var key="trade_"+str(from_resource)+"_"+str(to_resource)
 return key if RECIPES.has(key) else ""
static func label(key)->String:
 var row=RECIPES.get(key,{})
 if row.is_empty():return "無效交易"
 var names={"food":"食","wood":"木","iron":"鐵","stone":"石"}
 return "%d %s → %d %s" % [row.input,names[row.from],row.output,names[row.to]]
