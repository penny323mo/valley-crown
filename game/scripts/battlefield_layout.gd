extends RefCounted
## Public, fixed resource layouts. Trees/minerals are real harvestable obstacles.
## No gifts, combat changes, invisible zoning or impassable decorative terrain.
const Rules=preload("res://scripts/rules.gd")
# Mirrored islands break sight/movement around the four contested center iron
# deposits, leaving a straight center approach and two wider flanking lanes.
const IRONWOOD_WOOD=[Vector3(-8.5,0,3.5),Vector3(-7.5,0,3.5),Vector3(-6.5,0,3.5),Vector3(-8.5,0,4.5),Vector3(-7.5,0,4.5),Vector3(-6.5,0,4.5)]
const IRONWOOD_FOOD=[Vector3(10.5,0,7.5),Vector3(12.5,0,7.5),Vector3(10.5,0,9.5),Vector3(12.5,0,9.5),Vector3(-6.5,0,10.5),Vector3(-8.5,0,10.5)]
const IRONWOOD_FORWARD_IRON=[Vector3(-3.5,0,1.5),Vector3(-1.5,0,2.5)]
const IRONWOOD_FORWARD_STONE=[Vector3(-17.5,0,3.5),Vector3(-17.5,0,5.5)]
static func valid(id:String)->String:
 return id if id in ["valley","woodland","iron_crossroads"] else "valley"
static func supported(mode:String,victory:String)->bool:
 return mode in ["practice","standard","pressure"] and victory=="conquest"
static func title(id:String)->String:
 if valid(id)=="iron_crossroads":return "前線鐵谷"
 return "雙翼林地" if valid(id)=="woodland" else "經典谷地"
static func details(id:String)->String:
 if valid(id)=="iron_crossroads":return "中央是短路與爭奪鐵礦；兩翼分布前置糧食及石材，可繞路或建前線倉庫。基地附近礦區及資源總量不變。"
 return "中場林帶留有中央缺口；兩側有前置糧食與礦區，可繞路或正常伐木開路。" if valid(id)=="woodland" else "原有谷地配置，基地及中場資源位置不變。"
static func expansion_resources(id:String)->Array:
 var result=[]
 if valid(id)=="valley":
  # Preserve every original spawn index, including antipodal pair ordering.
  for team in 2:
   var sign_team=1.0 if team==0 else -1.0
   for i in 6:
    var p=Vector3(floorf(-13+(i%3)*1.5)+.5,0,floorf(8+floor(i/3.0)*1.5)+.5)
    result.append({"kind":"pine" if i%3 else "oak","pos":p*sign_team})
   for i in 3:result.append({"kind":"berry","pos":Vector3(floorf(-9+i*1.5)+.5,0,11.5)*sign_team})
  for p in [Vector3(-3.5,0,-1.5),Vector3(-.5,0,-1.5),Vector3(2.5,0,-1.5)]:
   result.append({"kind":"berry","pos":p});result.append({"kind":"berry","pos":-p})
  return result
 if valid(id)=="iron_crossroads":
  for team in 2:
   var side=1.0 if team==0 else -1.0
   for i in IRONWOOD_WOOD.size():
    result.append({"kind":"pine" if i%3 else "oak","pos":IRONWOOD_WOOD[i]*side})
   for p in IRONWOOD_FOOD:result.append({"kind":"berry","pos":p*side})
  return result
 for team in 2:
  var sign_team=1.0 if team==0 else -1.0
  for i in 6:result.append({"kind":"pine" if i%3 else "oak","pos":Vector3(-7.5+i,0,-1.5)*sign_team})
  for p in [Vector3(-12.5,0,2.5),Vector3(-12.5,0,4.5),Vector3(-10.5,0,4.5),Vector3(-10.5,0,2.5),Vector3(-1.5,0,7.5),Vector3(-3.5,0,7.5)]:
   result.append({"kind":"berry","pos":p*sign_team})
 return result
static func mineral_resources(id:String)->Array:
 var result=[]
 for team in 2:
  var sign_team=1.0 if team==0 else -1.0
  for kind in ["stone","iron"]:
   for i in Rules.MINERAL_POINTS[kind].size():
    var point=Rules.MINERAL_POINTS[kind][i]
    var p=Vector3(point[0],0,point[1])
    if valid(id)=="woodland" and i>=4:
     p=Vector3(-15.5,0,-1.5+(i-4)*2) if kind=="stone" else Vector3(-15.5+(i-4)*2,0,6.5)
    if valid(id)=="iron_crossroads" and i>=4:
     p=IRONWOOD_FORWARD_STONE[i-4] if kind=="stone" else IRONWOOD_FORWARD_IRON[i-4]
    result.append({"kind":kind,"pos":p*sign_team})
 return result
