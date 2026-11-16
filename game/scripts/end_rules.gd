extends RefCounted
## END01 conservative recovery predicate. Absence of soldiers alone is never enough.
## An attack-capable building is an alive own building whose type can deal damage,
## including an unfinished such building. This deliberately favors avoiding a false
## surrender; unknown recovery events must also keep recovery_possible true.
const IRRECOVERABLE_TICKS = 1200
const NO_PROGRESS_TICKS = 3600

static func irrecoverable(view: Dictionary) -> bool:
	return view.living_units==0 and view.attack_buildings==0 and view.training_items==0 \
		and view.food<50 and view.food+view.refundable_food<50 \
		and not view.recovery_possible
