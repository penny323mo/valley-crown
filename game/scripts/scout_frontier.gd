extends RefCounted
## Public-map reconnaissance preference, not enemy-location inference/access.
## Aim one sight radius ahead along own keep -> public map centre. Distance
## still bounds each preference; existing explored/attempted filters decide legality.
static func score(origin: Vector3, candidate: Vector3, own_keep: Vector3, sight: float) -> float:
	var heading=-own_keep.normalized() if own_keep.is_finite() else Vector3.ZERO
	var delta=candidate-origin
	return delta.length_squared()-2.0*maxf(0.0,sight)*delta.dot(heading)
