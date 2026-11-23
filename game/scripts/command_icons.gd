extends RefCounted
## Presentation-only model portraits and separate trade/upgrade symbols.
## ICONS contains only the sixteen actual-model renders, never authored SVGs.
## Names, prices, disabled states and all command callbacks remain on the Button.
const ICONS = {
	"villager":preload("res://assets/mature/ui/portraits/villager.png"),
	"scout":preload("res://assets/mature/ui/portraits/scout.png"),
	"spearman":preload("res://assets/mature/ui/portraits/spearman.png"),
	"archer":preload("res://assets/mature/ui/portraits/archer.png"),
	"cavalry":preload("res://assets/mature/ui/portraits/cavalry.png"),
	"siege":preload("res://assets/mature/ui/portraits/siege.png"),
	"wall":preload("res://assets/mature/ui/portraits/wall.png"),
	"farm":preload("res://assets/mature/ui/portraits/farm.png"),
	"house":preload("res://assets/mature/ui/portraits/house.png"),
	"storehouse":preload("res://assets/mature/ui/portraits/storehouse.png"),
	"barracks":preload("res://assets/mature/ui/portraits/barracks.png"),
	"range":preload("res://assets/mature/ui/portraits/range.png"),
	"stable":preload("res://assets/mature/ui/portraits/stable.png"),
	"tower":preload("res://assets/mature/ui/portraits/tower.png"),
	"workshop":preload("res://assets/mature/ui/portraits/workshop.png"),
	"town_center":preload("res://assets/mature/ui/portraits/town_center.png"),
}
const TRADE_ICONS = {
	"trade_iron_food":preload("res://assets/mature/ui/icons/trade_iron_food.svg"),
	"trade_stone_food":preload("res://assets/mature/ui/icons/trade_stone_food.svg"),
}
# These small silhouettes are upgrade identifiers, not model portraits.
const UPGRADE_ICONS = {
	"age2":preload("res://assets/mature/ui/icons/age2.svg"),
	"forged_blades":preload("res://assets/mature/ui/icons/forged_blades.svg"),
	"tempered_arrows":preload("res://assets/mature/ui/icons/tempered_arrows.svg"),
	"reinforced_armor":preload("res://assets/mature/ui/icons/reinforced_armor.svg"),
	"wheelbarrow":preload("res://assets/mature/ui/icons/wheelbarrow.svg"),
	"supply_station":preload("res://assets/mature/ui/icons/supply_station.svg"),
}
static func apply(button: Button, kind: String, prominent: bool=false) -> void:
	var texture: Texture2D=ICONS.get(kind,TRADE_ICONS.get(kind,UPGRADE_ICONS.get(kind)))
	if texture==null: return
	button.icon=texture
	button.expand_icon=true
	button.icon_alignment=HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("icon_max_width",40 if prominent else 32)
	button.add_theme_constant_override("h_separation",6)
	button.set_meta("command_icon_kind",kind)
	button.add_theme_color_override("icon_disabled_color",Color(0.55,0.55,0.55,0.7))
	button.set_meta("command_icon_base_width",button.custom_minimum_size.x)
	button.minimum_size_changed.connect(func(): _fit_portrait_width(button))
	_fit_portrait_width(button)

static func _fit_portrait_width(button: Button) -> void:
	# expand_icon deliberately excludes texture size from Godot's minimum.
	# Reserve the full display width alongside the widest unchanged text line.
	var font=button.get_theme_font("font")
	var font_size=button.get_theme_font_size("font_size")
	var text_width=0.0
	for line in button.text.split("\n"):
		text_width=maxf(text_width,font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)
	var margins=0.0
	for state in ["normal","hover","pressed","disabled"]:
		margins=maxf(margins,button.get_theme_stylebox(state).get_minimum_size().x)
	var width=maxf(float(button.get_meta("command_icon_base_width",0)),ceilf(text_width)+margins+button.get_theme_constant("icon_max_width")+button.get_theme_constant("h_separation"))
	if not is_equal_approx(button.custom_minimum_size.x,width):
		button.custom_minimum_size.x=width
