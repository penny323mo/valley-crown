class_name PublicMapRoutes
extends RefCounted
## Public immutable map layout. Roads are visual wear, NOT placement zones.
const Rules = preload("res://scripts/rules.gd")
const MAP_SIZE = Rules.MAP_SIZE
const HOME_OFFSET = Vector3(-14, 0, 14)
const PLAYER_HOME = Vector3(-25, 0, 24)
# Preserve the old economic neighborhood while inserting a broad midfield.
const PLAYER_BUILD_PLOTS: Array[Vector3] = [
	Vector3(-29, 0, 23), Vector3(-21, 0, 23), Vector3(-25, 0, 28),
	Vector3(-21, 0, 28), Vector3(-31, 0, 23),
]
const ENEMY_BUILD_PLOTS: Array[Vector3] = [
	Vector3(20, 0, -24), Vector3(25, 0, -29), Vector3(20, 0, -29),
	Vector3(25, 0, -20), Vector3(16, 0, -24),
]

static func home(team: int) -> Vector3:
	return PLAYER_HOME if team == 0 else -PLAYER_HOME

static func home_offset(team: int) -> Vector3:
	return HOME_OFFSET if team == 0 else -HOME_OFFSET

static func corridor_mask() -> Dictionary:
	# Soft, worn trails suggest movement without silently forbidding building.
	var mask: Dictionary = {}
	for team in 2:
		var sign_team = 1 if team == 0 else -1
		for step in 30:
			var p = Vector3(-25 + step * 0.65, 0, 20 - step * 0.6) * sign_team
			var c = Vector2i(floori(p.x + Rules.MAP_HALF), floori(p.z + Rules.MAP_HALF))
			mask[c] = true
	mask.make_read_only()
	return mask

static func build_plots(team: int, footprint_width: int) -> Array[Vector3]:
	# AI/default-preview hints only. Every other clear site uses the same rules.
	var plots: Array[Vector3] = []
	var anchors = PLAYER_BUILD_PLOTS if team == 0 else ENEMY_BUILD_PLOTS
	for base in anchors:
		plots.append(base + (Vector3(0.5, 0, 0.5) if footprint_width % 2 == 1 else Vector3.ZERO))
	return plots
