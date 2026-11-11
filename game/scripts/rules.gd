extends Resource
## Demo rules v2. One data source for player, AI, HUD and tests.
const BUILD_ID = "vc-542ddb524e45"
const VERSION = "0.3.0-progression-candidate"
# User-requested 2026-11-07 scale/buildability revision. Cell, unit, building,
# movement, sight and economic scales stay unchanged; only world extent grows.
const MAP_SIZE = 80
const MAP_HALF = MAP_SIZE / 2.0
const MAP_BORDER = 2
const MAP_LAST_PLAYABLE = MAP_SIZE - MAP_BORDER - 1
const MAP_WORLD_LIMIT = MAP_HALF - MAP_BORDER
const CAMERA_LIMIT = MAP_HALF - 5.0
const MAP_VERSION = "valley80-open-land-v1"
const TICK = 0.05
const POP_LIMIT = 50
# Public, immutable maximum and current radius for every Demo unit kind.
const UNIT_RADIUS = 0.35
const TIME_LIMIT = 2400.0
# BAL01 D0.2 values are transcribed unchanged. Progression policy is a candidate.
const CONTENT = preload("res://scripts/bal01_content.gd")
const UNIT_KINDS = ["villager","scout","spearman","archer","cavalry","siege"]
const RESOURCE_KINDS = ["pine","oak","berry","stone","iron"]
const BUILDABLE_KINDS = ["house","barracks","range","storehouse","farm","tower","stable","workshop"]
const COSTS = {
 "villager":{"food":50}, "scout":{"food":70}, "spearman":{"food":50,"wood":20},
 "archer":{"food":25,"wood":45}, "cavalry":{"food":90,"iron":35}, "siege":{"wood":160,"iron":70},
 "house":{"wood":50}, "storehouse":{"wood":80}, "barracks":{"wood":120}, "range":{"wood":120},
 "farm":{"wood":60}, "stable":{"wood":160}, "tower":{"wood":80,"stone":100}, "workshop":{"wood":180,"stone":80},
 "age2":{"food":350,"wood":150,"iron":50}
}
const TRAIN_TICKS = {"villager":300,"scout":400,"spearman":360,"archer":440,"cavalry":600,"siege":900,"age2":1800}
const TRAIN_TIME = {"villager":15.0,"scout":20.0,"spearman":18.0,"archer":22.0,"cavalry":30.0,"siege":45.0}
const ATTACK_TICKS = {"villager":30,"scout":30,"spearman":30,"archer":30,"cavalry":30,"siege":50,"tower":30}
const BUILD_TIME = {"house":20.0,"barracks":35.0,"range":35.0,"storehouse":25.0,"farm":15.0,"stable":45.0,"tower":45.0,"workshop":50.0}
const BAL_VERSION = "D0.2"
const FOOTPRINT = {"town_center":4,"house":2,"storehouse":2,"barracks":3,"range":3,"farm":3,"stable":3,"tower":2,"workshop":3}
const HP = {"town_center":1200,"barracks":500,"range":500,"house":250,"storehouse":300,"farm":120,"stable":600,"tower":600,"workshop":600,"villager":35,"scout":50,"spearman":60,"archer":40,"cavalry":110,"siege":140,"pine":150,"oak":150,"berry":200,"stone":400,"iron":400}
const ARMOR = {"town_center":2,"barracks":1,"range":1,"house":0,"storehouse":0,"farm":0,"stable":1,"tower":2,"workshop":1,"villager":0,"scout":0,"spearman":1,"archer":0,"cavalry":2,"siege":3}
const SIGHT = {"villager":6,"spearman":6,"archer":6,"scout":10,"cavalry":7,"siege":5,"town_center":8,"house":5,"storehouse":5,"barracks":5,"range":5,"farm":5,"stable":5,"tower":8,"workshop":5}
const SPEED = {"villager":2.0,"scout":3.2,"spearman":2.0,"archer":1.8,"cavalry":3.0,"siege":1.0}
const DAMAGE = {"villager":3,"scout":4,"spearman":6,"archer":5,"cavalry":10,"siege":6,"tower":8}
const RANGE = {"villager":1.1,"scout":1.1,"spearman":1.1,"archer":4.5,"cavalry":1.1,"siege":1.3,"tower":6.0}
const ATTACK_TIME = {"villager":1.5,"scout":1.5,"spearman":1.5,"archer":1.5,"cavalry":1.5,"siege":2.5,"tower":1.5}
const NAMES = {"town_center":"主堡", "barracks":"兵營", "range":"箭場", "house":"民居", "storehouse":"倉庫", "farm":"農田", "stable":"馬廄", "tower":"守望塔", "workshop":"工坊", "villager":"村民", "scout":"斥候", "spearman":"長槍兵", "archer":"弓手", "cavalry":"騎兵", "siege":"攻城車", "pine":"木材", "oak":"木材", "berry":"漿果", "stone":"石材", "iron":"鐵礦", "age2":"城防時代"}
# Legacy primary product remains available for old observers. Orders use products_for.
const PRODUCES = {"town_center":"villager","barracks":"spearman","range":"archer","stable":"cavalry","workshop":"siege"}
const AGE2_KINDS = ["stable","workshop","cavalry","siege"]
const RESOURCE_NAMES = {"food":"食", "wood":"木", "stone":"石", "iron":"鐵"}
# Explicit candidate geometric policy: new large actors use a swept disk.
const UNIT_RADII = {"villager":0.35,"scout":0.35,"spearman":0.35,"archer":0.35,"cavalry":0.55,"siege":0.65}
const MAX_UNIT_RADIUS = 0.65
static func products_for(building: String) -> Array:
 if building=="town_center": return ["villager","scout"]
 return [PRODUCES[building]] if PRODUCES.has(building) else []
static func cost_label(kind: String) -> String:
 var parts=PackedStringArray()
 for resource in COSTS[kind]: parts.append(RESOURCE_NAMES[resource]+" "+str(COSTS[kind][resource]))
 return " ".join(parts)

# Candidate map policy, cell-centered antipodal deposits; finite400 per node.
const MINERAL_POINTS = {
 "stone":[[-33.5,20.5],[-32.5,18.5],[-30.5,16.5],[-32.5,16.5],[-12.5,14.5],[-10.5,14.5]],
 "iron":[[-23.5,18.5],[-21.5,18.5],[-23.5,16.5],[-21.5,16.5],[-15.5,11.5],[-17.5,11.5]]
}
