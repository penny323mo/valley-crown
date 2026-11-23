import hashlib
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
pin = json.loads((HERE / "input-pin.json").read_text())
SCREEN_SIZES = [(568, 320), (844, 390)]


def digest(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def preflight(repo, engine=None):
    revision, expected = pin["source"], pin["game_tree"]
    assert subprocess.check_output(["git", "-C", repo, "rev-parse", f"{revision}:game"], text=True).strip() == expected
    for rel, sha in pin["source_files"].items():
        data = subprocess.check_output(["git", "-C", repo, "show", f"{revision}:{rel}"])
        assert hashlib.sha256(data).hexdigest() == sha, rel
    for name, sha in pin["qa_files"].items():
        assert digest(HERE / name) == sha, name
    if engine is not None:
        assert digest(engine) == pin["engine_sha256"], "Wrong 4.6.3 engine"
    print("Pinned tree, critical product bytes and QA fixture verified" + ("; pinned engine verified" if engine else "; engine not verified (metadata-only)"))


def compare(out, meta):
    from PIL import Image
    rows = {}
    traces = []
    for w,h in SCREEN_SIZES:
        key = f"{w}x{h}"
        folder = out / key
        report = json.loads((folder / "receipt.json").read_text())
        assert report["build"] == pin["build"] and report["viewport"] == [w,h]
        if meta:
            assert report["display"] == "headless" and not report["rendered"]
        else:
            assert report["display"] == "X11" and report["rendered"]
            assert report["rendering_method"] == "gl_compatibility" and "llvmpipe" in report["renderer"].lower()
            assert report["engine"]["hash"] == pin["engine_commit"]
        assert report["zoom"] == 30.0
        frames = report["frames"]
        assert report["final_bank"]["food"] == 350000
        assert [r["stage"] for r in frames] == list(range(5))
        assert [r["hp"] for r in frames] == [200, 150, 100, 50, 0]
        assert [r["tick"] for r in frames] == [0,766,1524,2326,3084]
        assert all(r["audit"] and r["stone_untouched"] and r["iron_untouched"] for r in frames)
        for k in ("center","stone_center","iron_center"):
            assert len({tuple(r[k]) for r in frames}) == 1
            at = frames[0][k]; assert 0 <= at[0] < w and 0 <= at[1] < h
        assert len({r["foliage_hash"] for r in frames[:-1]}) == 1
        assert len({r["fruit_hash"] for r in frames[:-1]}) == 4
        assert all(r["berry_alive"] and r["present"] and r["center_pick"] == r["berry_id"] for r in frames[:-1])
        assert not frames[-1]["berry_alive"] and not frames[-1]["present"] and frames[-1]["center_pick"] != frames[-1]["berry_id"]
        expected = {f"baseline-stage-{n}.png" for n in (0,3,4)} if not meta else set()
        assert {p.name for p in folder.glob("*.png")} == expected
        assert {r["png"]["filename"] for r in frames if "png" in r} == expected
        pngs=[]
        for r in frames:
            if "png" not in r:
                continue
            got = r["png"];p=folder / got["filename"]
            assert digest(p) == got["sha256"]
            with Image.open(p) as im:
                assert im.format == "PNG" and im.size == (w,h)
                im.verify()
            assert got["draws"] > 0 and got["primitives"] > 0
            pngs.append(got)
        rows[key]={"camera":report["camera"],"pngs":pngs,"nodes":{k:frames[0][k] for k in ("berry_id","stone_id","iron_id","center","stone_center","iron_center")}}
        traces.append([(r["stage"],r["hp"],r["tick"],r["bank"]) for r in frames])
    assert traces[0] == traces[1]
    receipt={"build":pin["build"],"mode":"METADATA_ONLY" if meta else "RENDERED_GODOT_NATIVE","views":rows,
             "scope":"Controlled spawned geometry and workers, real matched harvest/deposit. No device or design validation."}
    (out / ("metadata-receipt.json" if meta else "verified-render-receipt.json")).write_text(json.dumps(receipt,indent=2)+"\n")
    print("Exact-build baseline receipts verified; no PNGs expected" if meta else "Six original baseline Godot PNGs verified, no image editing")


mode = sys.argv[1]
if mode == "preflight":
    preflight(*sys.argv[2:])
else:
    assert mode in ("rendered", "metadata") and len(sys.argv) == 3
    compare(Path(sys.argv[2]),mode=="metadata")
