"""Rebuild the licensed product UI subset from the pinned official Noto TC font.
Pure font data processing; no engine, OS font installation or network."""
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools import subset
import argparse,hashlib,json
p=argparse.ArgumentParser();p.add_argument("--root",type=Path,required=True);p.add_argument("--source",type=Path,required=True);a=p.parse_args()
expected="dce08bd4fd91aa8aa76ed8fea4b694c2dfb8550f67871e326843212ddbeb88b4"
assert hashlib.sha256(a.source.read_bytes()).hexdigest()==expected
target=a.root/"assets/fonts/ui_tc.otf";old=TTFont(target);required=set(old.getBestCmap());old.close()
required.update(range(32,127))
for path in (a.root/"scripts").rglob("*.gd"):
 required.update(ord(c) for c in path.read_text() if ord(c)>=128)
font=TTFont(a.source,recalcTimestamp=False)
missing=required-set(font.getBestCmap())
assert not missing,sorted(missing)
options=subset.Options();options.recalc_timestamp=False;options.name_IDs=["*"];options.name_legacy=True;options.name_languages=["*"]
worker=subset.Subsetter(options=options);worker.populate(unicodes=sorted(required));worker.subset(font)
names={1:"Valley Crown UI",2:"Regular",3:"ValleyCrownUI-Regular-20261112",4:"Valley Crown UI Regular",6:"ValleyCrownUI-Regular",16:"Valley Crown UI",17:"Regular"}
for record in font["name"].names:
 if record.nameID in names:record.string=names[record.nameID].encode(record.getEncoding())
if "CFF " in font:
 cff=font["CFF "].cff;cff.fontNames=["ValleyCrownUI-Regular"]
 for top in cff.topDictIndex:
  top.FamilyName="Valley Crown UI";top.FullName="Valley Crown UI Regular"
font.save(target);font.close()
verify=TTFont(target);coverage=set(verify.getBestCmap());assert required<=coverage;verify.close()
receipt={"upstream":"https://raw.githubusercontent.com/notofonts/noto-cjk/Sans2.004/Sans/OTF/TraditionalChinese/NotoSansCJKtc-Regular.otf","upstream_sha256":expected,"license":"assets/fonts/NOTO-LICENSE.txt (SIL Open Font License 1.1)","renamed_family":"Valley Crown UI","subset_sha256":hashlib.sha256(target.read_bytes()).hexdigest(),"required_codepoints":sorted(required),"coverage_count":len(coverage),"bytes":target.stat().st_size,"scope":"Base UI glyphs plus all current runtime GDScript non-ASCII text; data coverage, not render acceptance"}
(a.root/"reports/ui-font-source.json").write_text(json.dumps(receipt,indent=2)+"\n")
print(json.dumps({k:v for k,v in receipt.items() if k!="required_codepoints"}))
