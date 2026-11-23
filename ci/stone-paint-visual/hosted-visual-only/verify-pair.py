import hashlib
import json
import sys
from pathlib import Path
from PIL import Image

root = Path(sys.argv[1])
report = {"scope": "Software-rendered visual-only comparison, not iPhone or frame-time validation", "comparison": {}}
issues = []
for w, h in ((390, 844), (844, 390)):
    key = f"{w}x{h}"
    folders = [root / role / key for role in ("baseline", "paint")]
    a, b = (json.loads((p / "journey.json").read_text()) for p in folders)
    for d in (a, b):
        assert d["display"] != "headless" and d["rendering_method"] == "gl_compatibility"
        assert "llvmpipe" in d["video_adapter"].lower() and d["size"] == [w, h]
        assert [(r["stage"], r["hp"]) for r in d["stages"]] == [
            (0, 400.0), (1, 300.0), (2, 200.0), (3, 100.0)]
        assert all(r["audit"] and r["pick"] == r["stone_id"] == r["target_id"] for r in d["stages"])
        ticks = [r["tick"] for r in d["stages"]]
        assert ticks[0] == 0 and ticks == sorted(set(ticks))
        assert [r["stage"] for r in d["renders"]] == [0, 2, 3]
    assert a["stages"] == b["stages"], "world/target/ledger mismatch"
    rows = []
    for u, v in zip(a["renders"], b["renders"], strict=True):
        assert u["roi"] == v["roi"] and u["stage"] == v["stage"], "camera/geometry mismatch"
        assert u["draws"] == v["draws"] and u["draws"] > 0 and u["primitives"] == v["primitives"], "draw parity failed"
        images = []
        for folder, frame in zip(folders, (u, v)):
            p = folder / f"stage-{frame['stage']}.png"
            assert hashlib.sha256(p.read_bytes()).hexdigest() == frame["sha256"]
            with Image.open(p) as im:
                assert im.format == "PNG" and im.size == (w, h)
                images.append(list(im.convert("RGB").getdata()))
        lx, ly, rx, ry = u["roi"]
        assert 0 <= lx < rx <= w and 0 <= ly < ry <= h
        stage = u["stage"]
        inside = outside = visible_delta = 0
        for i, (first, second) in enumerate(zip(*images, strict=True)):
            delta = max(abs(x - y) for x, y in zip(first, second))
            if not delta:
                continue
            if lx <= i % w < rx and ly <= i // w < ry:
                inside += 1
                visible_delta += delta >= 12
            else:
                outside += 1
        rows.append({"stage": stage, "roi": u["roi"], "roi_changed_pixels": inside,
                     "roi_delta_at_least_12_pixels": visible_delta, "outside_changed_pixels": outside,
                     "draws_identical": u["draws"], "primitives_identical": u["primitives"]})
        if (stage == 0 and (inside or outside)) or (stage != 0 and outside):
            issues.append(f"{key} stage {stage}: image is not an isolated deterministic A/B")
    report["comparison"][key] = rows
report["issues"] = issues
report["visual_acceptance"] = "REVIEW_NOT_DONE" if not issues else "INCONCLUSIVE_CAPTURE_VARIANCE"
(root / "compare-receipt.json").write_text(json.dumps(report, indent=2) + "\n")
if issues:
    raise SystemExit("; ".join(issues))
print("Three stages x two viewports matched identity/draw/scene parity; review raw captures next.")
