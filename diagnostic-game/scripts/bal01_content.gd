extends RefCounted
## Isolated BAL01 D0.2 data and arithmetic, not a world or content unlock gate.
## Exact plan transcription. No placement, producer, age, movement or AI policy.
## Distance/speed values use thousandths of a grid cell, not resource milli-units.
## Only the resolver's integer damage may be passed to the attack ledger after
## the caller independently validates ownership, visibility, range and cooldown.

const BAL_VERSION = "D0.2"
const TICKS_PER_SECOND = 20
const DISTANCE_SCALE = 1000

const UNITS = {
	"villager": {"hp":35,"armor":0,"damage":3,"range_milli":1100,"attack_ticks":30,"speed_milli":2000,"sight":6,"cost":{"food":50},"train_ticks":300},
	"scout": {"hp":50,"armor":0,"damage":4,"range_milli":1100,"attack_ticks":30,"speed_milli":3200,"sight":10,"cost":{"food":70},"train_ticks":400},
	"spearman": {"hp":60,"armor":1,"damage":6,"range_milli":1100,"attack_ticks":30,"speed_milli":2000,"sight":6,"cost":{"food":50,"wood":20},"train_ticks":360},
	"archer": {"hp":40,"armor":0,"damage":5,"range_milli":4500,"attack_ticks":30,"speed_milli":1800,"sight":6,"cost":{"food":25,"wood":45},"train_ticks":440},
	"cavalry": {"hp":110,"armor":2,"damage":10,"range_milli":1100,"attack_ticks":30,"speed_milli":3000,"sight":7,"cost":{"food":90,"iron":35},"train_ticks":600},
	"siege": {"hp":140,"armor":3,"damage":6,"range_milli":1300,"attack_ticks":50,"speed_milli":1000,"sight":5,"cost":{"wood":160,"iron":70},"train_ticks":900}
}

const BUILDINGS = {
	"town_center": {"footprint":4,"hp":1200,"armor":2,"sight":8,"population":10},
	"house": {"footprint":2,"hp":250,"armor":0,"sight":5,"population":5,"cost":{"wood":50},"build_ticks":400},
	"storehouse": {"footprint":2,"hp":300,"armor":0,"sight":5,"cost":{"wood":80},"build_ticks":500},
	"barracks": {"footprint":3,"hp":500,"armor":1,"sight":5,"cost":{"wood":120},"build_ticks":700},
	"range": {"footprint":3,"hp":500,"armor":1,"sight":5,"cost":{"wood":120},"build_ticks":700},
	"farm": {"footprint":3,"hp":120,"armor":0,"sight":5,"cost":{"wood":60},"build_ticks":300},
	"stable": {"footprint":3,"hp":600,"armor":1,"sight":5,"cost":{"wood":160},"build_ticks":900},
	"tower": {"footprint":2,"hp":600,"armor":2,"sight":8,"cost":{"wood":80,"stone":100},"build_ticks":900,"damage":8,"range_milli":6000,"attack_ticks":30,"limit":2},
	"workshop": {"footprint":3,"hp":600,"armor":1,"sight":5,"cost":{"wood":180,"stone":80},"build_ticks":1000}
}

const UNIT_COUNTER_BONUSES = {
	"spearman": {"cavalry":12},
	"archer": {"spearman":3},
	"cavalry": {"archer":5}
}
const SIEGE_BUILDING_BONUS = 24

static func unit_profile(kind: String) -> Dictionary:
	return UNITS[kind].duplicate(true) if UNITS.has(kind) else {}

static func building_profile(kind: String) -> Dictionary:
	return BUILDINGS[kind].duplicate(true) if BUILDINGS.has(kind) else {}

static func unit_kinds() -> Array:
	return UNITS.keys()

static func building_kinds() -> Array:
	return BUILDINGS.keys()

static func resolve_damage(attacker_kind: String, target_kind: String) -> Dictionary:
	var attacker: Dictionary = {}
	if UNITS.has(attacker_kind):
		attacker = UNITS[attacker_kind]
	elif BUILDINGS.has(attacker_kind) and BUILDINGS[attacker_kind].has("damage"):
		attacker = BUILDINGS[attacker_kind]
	else:
		return {"ok":false,"reason":"unsupported_attacker"}
	var target: Dictionary = {}
	var target_is_building: bool = BUILDINGS.has(target_kind)
	if UNITS.has(target_kind):
		target = UNITS[target_kind]
	elif target_is_building:
		target = BUILDINGS[target_kind]
	else:
		return {"ok":false,"reason":"unsupported_target"}
	var bonus: int = 0
	if attacker_kind == "siege" and target_is_building:
		bonus = SIEGE_BUILDING_BONUS
	elif UNIT_COUNTER_BONUSES.has(attacker_kind):
		bonus = UNIT_COUNTER_BONUSES[attacker_kind].get(target_kind, 0)
	var base: int = attacker.damage
	var armor: int = target.armor
	return {"ok":true,"damage":maxi(1, base + bonus - armor),"base":base,"bonus":bonus,"armor":armor}
