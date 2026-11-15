extends SceneTree
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func scan(path:String,font:Font,missing:Dictionary):
 for file in DirAccess.get_files_at(path):
  if file.ends_with(".gd"):
   var content=FileAccess.get_file_as_string(path.path_join(file))
   for i in content.length():
    var code=content.unicode_at(i)
    if code>=128 and not font.has_char(code):missing[code]=true
 for child in DirAccess.get_directories_at(path):scan(path.path_join(child),font,missing)
func _initialize():call_deferred("run")
func run():
 var font=load("res://assets/fonts/ui_tc.otf") as Font
 check("bundled UI font loads",font!=null)
 var missing={}
 scan("res://scripts",font,missing)
 check("bundled UI font covers every runtime non ASCII codepoint",missing.is_empty())
 var challenge_ok=true
 for word in ["三波守城挑戰","單人劇本挑戰","增援","準備","整備"]:
  for i in word.length():challenge_ok=challenge_ok and font.has_char(word.unicode_at(i))
 check("challenge labels have actual bundled glyphs",challenge_ok)
 print(JSON.stringify({"suite":"ui_glyph_coverage_contract","checks":checks,"failed":checks.filter(func(c):return not c.passed).size(),"missing_codepoints":missing.keys()}))
 quit(0 if checks.all(func(c):return c.passed) else 1)
