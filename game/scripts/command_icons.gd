extends RefCounted
## Original functional command pictograms; not final character artwork.
const ICONS = {
	"villager":preload("res://assets/mature/ui/icons/villager.svg"),
	"scout":preload("res://assets/mature/ui/icons/scout.svg"),
	"spearman":preload("res://assets/mature/ui/icons/spearman.svg"),
	"archer":preload("res://assets/mature/ui/icons/archer.svg"),
	"cavalry":preload("res://assets/mature/ui/icons/cavalry.svg"),
	"siege":preload("res://assets/mature/ui/icons/siege.svg"),
	"wall":preload("res://assets/mature/ui/icons/wall.svg"),
	"farm":preload("res://assets/mature/ui/icons/farm.svg"),
	"house":preload("res://assets/mature/ui/icons/house.svg"),
	"storehouse":preload("res://assets/mature/ui/icons/storehouse.svg"),
	"barracks":preload("res://assets/mature/ui/icons/barracks.svg"),
	"range":preload("res://assets/mature/ui/icons/range.svg"),
	"stable":preload("res://assets/mature/ui/icons/stable.svg"),
	"tower":preload("res://assets/mature/ui/icons/tower.svg"),
	"workshop":preload("res://assets/mature/ui/icons/workshop.svg"),
	"town_center":preload("res://assets/mature/ui/icons/town_center.svg"),
}
static func apply(button: Button, kind: String) -> void:
	if not ICONS.has(kind): return
	button.icon=ICONS[kind]
	button.expand_icon=true
	button.icon_alignment=HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("icon_max_width",28)
	button.add_theme_constant_override("h_separation",6)
	button.set_meta("command_icon_kind",kind)
