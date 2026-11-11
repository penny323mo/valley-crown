extends Resource
## Demo rules v2. One data source for player, AI, HUD and tests.
const BUILD_ID = "vc-f136b31c3e2d"
const VERSION = "0.2.2-map80-candidate"
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
const POP_LIMIT = 20
# Public, immutable maximum and current radius for every Demo unit kind.
const UNIT_RADIUS = 0.35
const TIME_LIMIT = 2400.0
const COSTS = {
	"villager":{"food":50}, "spearman":{"food":50,"wood":20},
	"archer":{"food":25,"wood":45}, "house":{"wood":50},
	"barracks":{"wood":120}, "range":{"wood":120}, "storehouse":{"wood":80}
}
const TRAIN_TICKS = {"villager":300,"spearman":360,"archer":440}
const TRAIN_TIME = {"villager":TRAIN_TICKS.villager*TICK,"spearman":TRAIN_TICKS.spearman*TICK,"archer":TRAIN_TICKS.archer*TICK}
const ATTACK_TICKS = {"villager":30,"scout":30,"spearman":30,"archer":30}
const BUILD_TIME = {"house":20.0,"barracks":35.0,"range":35.0,"storehouse":25.0}
const BAL_VERSION = "D0.2"
const FOOTPRINT = {"town_center":4,"house":2,"storehouse":2,"barracks":3,"range":3}
const HP = {"town_center":1200,"barracks":500,"range":500,"house":250,"storehouse":300,"villager":35,"scout":50,"spearman":60,"archer":40,"pine":150,"oak":150,"berry":200}
const ARMOR = {"town_center":2,"barracks":1,"range":1,"house":0,"storehouse":0,"villager":0,"scout":0,"spearman":1,"archer":0}
# Accepted BAL01 current-Demo sight, measured from the entity center cell.
# "Other buildings 5" has no construction exception: ordinary sites also use 5.
# This literal stage interpretation adds no new balance acceptance or v1 defaults.
const SIGHT = {"villager":6,"spearman":6,"archer":6,"scout":10,"town_center":8,"house":5,"storehouse":5,"barracks":5,"range":5}
const SPEED = {"villager":2.0,"scout":3.2,"spearman":2.0,"archer":1.8}
const DAMAGE = {"villager":3,"scout":4,"spearman":6,"archer":5}
const RANGE = {"villager":1.1,"scout":1.1,"spearman":1.1,"archer":4.5}
const ATTACK_TIME = {"villager":ATTACK_TICKS.villager*TICK,"scout":ATTACK_TICKS.scout*TICK,"spearman":ATTACK_TICKS.spearman*TICK,"archer":ATTACK_TICKS.archer*TICK}
const NAMES = {"town_center":"主堡", "barracks":"兵營", "range":"箭場", "house":"民居", "storehouse":"倉庫", "villager":"村民", "scout":"斥候", "spearman":"長槍兵", "archer":"弓手", "pine":"木材", "oak":"木材", "berry":"漿果"}
const PRODUCES = {"town_center":"villager","barracks":"spearman","range":"archer"}
