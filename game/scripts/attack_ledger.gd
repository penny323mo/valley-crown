extends RefCounted
## Private match authority, never a FactionView or command interface.
## IDs are dense and never reused/pruned during a match. Exact payload bytes,
## not hashes, distinguish a replay from a conflicting use of an issued ID.
const Rules = preload("res://scripts/rules.gd")
const RECORD_BYTES = 80 # Four int64 values and six float64 coordinates; ID is its slot + 1.
const MATCH_TICKS = int(Rules.TIME_LIMIT / Rules.TICK)
const MAX_ATTACKS = 2 * Rules.POP_LIMIT * (ceili(float(MATCH_TICKS) / 30) + 1 + ceili(float(MATCH_TICKS) / 300))
var _records = PackedByteArray()
var _settled_through = 0

func next_attack_id() -> int:
	return _records.size() / RECORD_BYTES + 1

func _encode(event: Dictionary) -> PackedByteArray:
	var bytes = PackedByteArray()
	bytes.resize(RECORD_BYTES)
	for i in 4:
		bytes.encode_s64(i * 8, event[["release_tick", "attacker_id", "target_id", "damage"][i]])
	var coordinates = [event.origin.x, event.origin.y, event.origin.z, event.endpoint.x, event.endpoint.y, event.endpoint.z]
	for i in 6: bytes.encode_double(32 + i * 8, coordinates[i])
	return bytes

func event(attack_id: int) -> Dictionary:
	if attack_id < 1 or attack_id >= next_attack_id(): return {}
	var start = (attack_id - 1) * RECORD_BYTES
	return {"attack_id": attack_id, "release_tick": _records.decode_s64(start),
		"attacker_id": _records.decode_s64(start + 8), "target_id": _records.decode_s64(start + 16),
		"damage": _records.decode_s64(start + 24),
		"origin": Vector3(_records.decode_double(start + 32), _records.decode_double(start + 40), _records.decode_double(start + 48)),
		"endpoint": Vector3(_records.decode_double(start + 56), _records.decode_double(start + 64), _records.decode_double(start + 72))}

func issue(release_tick: int, attacker_id: int, target_id: int, damage: int, origin: Vector3, endpoint: Vector3) -> Dictionary:
	# Only game._release_attack calls this, after world validation. Callers cannot
	# supply an attack ID or damage through any player/AI command.
	var attack_id = next_attack_id()
	if attack_id > MAX_ATTACKS: return {"ok": false, "applied": false, "reason": "MATCH_ATTACK_LIMIT"}
	var frozen = {"attack_id": attack_id, "release_tick": release_tick, "attacker_id": attacker_id,
		"target_id": target_id, "damage": damage, "origin": origin, "endpoint": endpoint}
	_records.append_array(_encode(frozen))
	return {"ok": true, "applied": true, "event": frozen}

func replay(candidate: Dictionary) -> Dictionary:
	if candidate.size() != 7: return {"ok": false, "applied": false, "reason": "INVALID_PAYLOAD"}
	for key in ["attack_id", "release_tick", "attacker_id", "target_id", "damage"]:
		if not candidate.has(key) or not candidate[key] is int:
			return {"ok": false, "applied": false, "reason": "INVALID_PAYLOAD"}
	for key in ["origin", "endpoint"]:
		if not candidate.has(key) or not candidate[key] is Vector3:
			return {"ok": false, "applied": false, "reason": "INVALID_PAYLOAD"}
	var attack_id: int = candidate.attack_id
	if attack_id < 1 or attack_id >= next_attack_id():
		return {"ok": false, "applied": false, "reason": "UNKNOWN_ATTACK_ID"}
	var start = (attack_id - 1) * RECORD_BYTES
	if _encode(candidate) != _records.slice(start, start + RECORD_BYTES):
		return {"ok": false, "applied": false, "reason": "CONFLICTING_ATTACK_ID"}
	return {"ok": true, "applied": false, "reason": "DUPLICATE"}

func settle() -> Dictionary:
	# Dense IDs plus a settled prefix are sufficient: releases cannot be removed,
	# reordered or admitted by replay. No survival/visibility revalidation here.
	var damage = {}
	var issued = next_attack_id() - 1
	for attack_id in range(_settled_through + 1, issued + 1):
		var start = (attack_id - 1) * RECORD_BYTES
		var target_id = _records.decode_s64(start + 16)
		damage[target_id] = damage.get(target_id, 0) + _records.decode_s64(start + 24)
	_settled_through = issued
	return damage

func snapshot() -> Dictionary:
	# Canonical, value-only private test/save-boundary input. This is not save/load.
	return {"next_attack_id": next_attack_id(), "settled_through": _settled_through,
		"record_bytes": RECORD_BYTES, "max_attacks": MAX_ATTACKS, "records_hex": _records.hex_encode()}

func storage_bytes() -> int:
	return _records.size()
