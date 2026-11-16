extends RefCounted
## Narrow work-routing view, NOT a complete FactionView/HUD/AI memory system.
## Receives observed entity snapshots only, never full navigation/world data.
## Visibility matches GameSession._visible_to (physical footprint intersection).
## Remembered entirely unseen static footprints remain frozen.
const Rules = preload("res://scripts/rules.gd")
var grid := AStarGrid2D.new()
var revision := 0
var resources: Dictionary = {}
var structures: Dictionary = {}
var known_obstacles: Dictionary = {}
var observed_solids: Dictionary = {}
var own_solids: Dictionary = {}
var resource_observed_at: Dictionary = {}
var obstacle_observed_at: Dictionary = {}
var cell_observed_at: Dictionary = {}
const UNKNOWN_POLICY := "free_except_fixed_public_boundary"

func _init() -> void:
	grid.region = Rect2i(0, 0, Rules.MAP_SIZE, Rules.MAP_SIZE); grid.update()
	for y in Rules.MAP_SIZE:
		for x in Rules.MAP_SIZE:
			if x < Rules.MAP_BORDER or y < Rules.MAP_BORDER or x > Rules.MAP_LAST_PLAYABLE or y > Rules.MAP_LAST_PLAYABLE:
				grid.set_point_solid(Vector2i(x, y))

func observe(seen_static: Dictionary, owned: Dictionary, own_cells: Dictionary, tick: int) -> Dictionary:
	var changed := {}
	var records_changed := false
	for id in seen_static:
		var record: Dictionary = seen_static[id]
		obstacle_observed_at[id] = tick
		for cell in record.cells: cell_observed_at[cell] = tick
		if known_obstacles.get(id, {}) != record:
			known_obstacles[id] = record.duplicate(true); records_changed = true
		if record.category == "resource":
			resource_observed_at[id] = tick
			resources[id] = record.duplicate(true)
	if structures != owned:
		structures = owned.duplicate(true); records_changed = true
	# Only obstacle cells can change after fixed boundaries are initialized.
	# Cost follows observed geometry, not the expanded map area every tick.
	var touched: Dictionary = {}
	for cell in observed_solids: touched[cell] = true
	for cell in own_solids: touched[cell] = true
	own_solids = own_cells.duplicate()
	observed_solids.clear()
	for record in known_obstacles.values():
		if record.alive:
			for cell in record.cells: observed_solids[cell] = true
	for cell in observed_solids: touched[cell] = true
	for cell in own_solids: touched[cell] = true
	for cell in touched:
		if not grid.region.has_point(cell): continue
		var solid: bool = cell.x < Rules.MAP_BORDER or cell.y < Rules.MAP_BORDER or cell.x > Rules.MAP_LAST_PLAYABLE or cell.y > Rules.MAP_LAST_PLAYABLE or observed_solids.has(cell) or own_solids.has(cell)
		if grid.is_point_solid(cell) != solid:
			grid.set_point_solid(cell, solid); changed[cell] = true
	if records_changed or not changed.is_empty(): revision += 1
	return {"cells": changed, "records_changed": records_changed}
