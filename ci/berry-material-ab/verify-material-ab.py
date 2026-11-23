import json
import sys
from pathlib import Path
from PIL import Image

root=Path(sys.argv[1])
report={}
for size in ("568x320","844x390"):
    paths=[root/r/size for r in ("baseline","candidate")]
    a,b=(json.loads((p/"receipt.json").read_text()) for p in paths)
    assert {k:v for k,v in a.items() if k!="frames"} == {k:v for k,v in b.items() if k!="frames"}
    for x,y in zip(a["frames"],b["frames"],strict=True):
        assert {k:v for k,v in x.items() if k!="png"} == {k:v for k,v in y.items() if k!="png"}
    bx,by=map(round,a["frames"][0]["center"])
    # Conservative projected foliage vicinity: 17x17 at 568, 19x19 at 844.
    # This is a containment witness, not a foliage segmentation mask.
    # Keep incidental worker overlap in the raw PNG; excluded from art judgment.
    half=8 if size=="568x320" else 9
    rows=[]
    for stage in (0,3,4):
        da,db=(r["frames"][stage]["png"] for r in (a,b))
        assert [da["draws"],da["primitives"]]==[db["draws"],db["primitives"]]
        with Image.open(paths[0]/da["filename"]) as i, Image.open(paths[1]/db["filename"]) as j:
            w,h=i.size; assert j.size==(w,h)
            strong=set();outside=0;changed=0
            for ind,(p,q) in enumerate(zip(i.convert("RGB").getdata(),j.convert("RGB").getdata(),strict=True)):
                delta=max(abs(u-v) for u,v in zip(p,q))
                if not delta:continue
                changed+=1
                x,y=ind%w,ind//w
                if abs(x-bx)>half or abs(y-by)>half:
                    outside+=1
                elif delta>=12:
                    strong.add((x,y))
            contiguous=any(all((x+dx,y+dy) in strong for dx,dy in ((1,0),(0,1),(1,1))) for x,y in strong)
        # Variance outside blend-free diffuse foliage is inconclusive, not a win.
        assert outside==0 and (stage==3 or changed==0), (size,stage,"uncontrolled pixel differences")
        rows.append({"stage":stage,"center":[bx,by],"roi_half":half,"changed_pixels":changed,
                     "strong_pixels":len(strong),"strong_contiguous_2x2_candidate":contiguous,
                     "draws":da["draws"],"primitives":da["primitives"]})
    report[size]=rows
(root/"matched-ab-receipt.json").write_text(json.dumps({"scope":"Held isolated art test; not shipped or player-tested; confirm 2x2 cue actually belongs to exposed foliage.",
    "capture":report,"eligible_for_blind_review":all(v[1]["strong_contiguous_2x2_candidate"] for v in report.values())},indent=2)+"\n")
