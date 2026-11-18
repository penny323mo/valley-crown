extends SceneTree
const Game=preload("res://scripts/game.gd")
var checks=[]
func check(name,ok):checks.append({"name":name,"ok":bool(ok)})
func _initialize():call_deferred("run")
func run():
 var g=Game.new();g.test_mode=true;g.skirmish_mode="standard";root.add_child(g);g.set_process(false);await process_frame
 var house={"id":900,"kind":"house","pos":Vector3.ZERO,"owned":true,"alive":true,"category":"building","built":true}
 check("adjacent own footprint is not selected",not g._ai_building_lane_clear("house",Vector3(2,0,0),[house]))
 check("one empty grid cell is not enough",not g._ai_building_lane_clear("house",Vector3(3,0,0),[house]))
 check("two empty grid cells remain permitted",g._ai_building_lane_clear("house",Vector3(4,0,0),[house]))
 var unfinished=house.duplicate(true);unfinished.built=false
 check("unfinished paid construction reserves its footprint",not g._ai_building_lane_clear("house",Vector3(3,0,0),[unfinished]))
 var dead=house.duplicate(true);dead.alive=false
 check("dead own building does not reserve new lane",g._ai_building_lane_clear("house",Vector3(2,0,0),[dead]))
 var enemy=house.duplicate(true);enemy.owned=false
 check("policy does not derive lane from enemy building",g._ai_building_lane_clear("house",Vector3(2,0,0),[enemy]))
 var wall=house.duplicate(true);wall.kind="wall"
 check("wall formation remains outside ordinary spacing policy",g._ai_building_lane_clear("house",Vector3(2,0,0),[wall]))
 var tree=house.duplicate(true);tree.category="resource";tree.kind="tree"
 check("natural obstacle clearance remains placement authority",g._ai_building_lane_clear("house",Vector3(2,0,0),[tree]))
 check("mixed odd workshop footprint obeys cell spacing",not g._ai_building_lane_clear("workshop",Vector3(3.5,0,.5),[house]) and g._ai_building_lane_clear("workshop",Vector3(4.5,0,.5),[house]))
 var before=house.duplicate(true);var commands=g.commands.duplicate(true);var bank=g.economy.bank_milli(1).duplicate(true)
 g._ai_building_lane_clear("house",Vector3(2,0,0),[house])
 check("selection policy is read only and cannot pay or submit",house==before and commands==g.commands and bank==g.economy.bank_milli(1))
 check("tower policy enforces the same building gap",not g._ai_progression_spacing_clear("tower",Vector3(2,0,0),[house]))
 for kind in ["house","barracks","range","workshop","farm","storehouse","stable","wall"]:
  check("non-tower "+kind+" preserves ordinary placement selection",g._ai_progression_spacing_clear(kind,Vector3.ZERO,[house]))
 var failed=checks.filter(func(c):return not c.ok).size()
 print(JSON.stringify({"suite":"ai_building_spacing_contract","checks":checks,"failed":failed,"scope":"Pure tower-only selection policy and unchanged non-tower delegation; no reachability or match-benefit assertion"}))
 g.free();quit(1 if failed else 0)
