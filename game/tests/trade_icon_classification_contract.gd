extends SceneTree
const Icons=preload("res://scripts/command_icons.gd")
var checks=[]
var presses=0
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred("run")
func run():
 var kinds=Icons.TRADE_ICONS.keys();kinds.sort()
 check("exact two trade symbol kinds",kinds==["trade_iron_food","trade_stone_food"])
 var models=Icons.ICONS.keys();models.sort()
 check("trade symbols excluded from exact sixteen model portrait kinds",models==["archer","barracks","cavalry","farm","house","range","scout","siege","spearman","stable","storehouse","tower","town_center","villager","wall","workshop"] and kinds.all(func(k):return not Icons.ICONS.has(k)))
 for kind in kinds:
  var texture=Icons.TRADE_ICONS[kind]
  check(kind+" exact authored SVG path",texture.resource_path=="res://assets/mature/ui/icons/"+kind+".svg")
  check(kind+" exact32px symbol dimensions",texture.get_width()==32 and texture.get_height()==32)
  var b=Button.new();b.text="100 鐵 → 60 食\n處理 15 秒（另計排隊）";b.disabled=true;root.add_child(b)
  b.pressed.connect(func():presses+=1)
  var original=b.text;var count=b.pressed.get_connections().size()
  Icons.apply(b,kind)
  check(kind+" apply explicitly resolves trade class",b.icon==texture and b.get_meta("command_icon_kind")==kind and b.get_theme_constant("icon_max_width")==32)
  check(kind+" apply preserves price disabled callback",b.text==original and b.disabled and b.pressed.get_connections().size()==count and presses==0)
  b.free()
 var portrait=Button.new();root.add_child(portrait);Icons.apply(portrait,"villager",true)
 check("model portrait apply remains256source40display",portrait.icon==Icons.ICONS.villager and portrait.icon.get_width()==256 and portrait.get_theme_constant("icon_max_width")==40)
 var previous=portrait.icon;var width=portrait.custom_minimum_size;var meta=portrait.get_meta("command_icon_kind")
 Icons.apply(portrait,"unknown_trade_symbol")
 check("unknown kind leaves existing button untouched",portrait.icon==previous and portrait.custom_minimum_size==width and portrait.get_meta("command_icon_kind")==meta)
 portrait.free()
 var empty=Button.new();root.add_child(empty);Icons.apply(empty,"trade_iron_wood")
 check("unlisted recipe receives no invented icon",empty.icon==null and not empty.has_meta("command_icon_kind"));empty.free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"trade_icon_classification_contract","checks":checks,"failed":failed,"scope":"Exact model-versus-symbol registry and presentation-only application; no trade economics or screenshot claim"}));quit(1 if failed else 0)
