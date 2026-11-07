"""Source-backed AnimationMixer applied quaternion expectation; raw track evaluator stays immutable."""
import math
from evaluate_held_tracks import f32, reference

def normalized(q):
 assert len(q)==4 and all(math.isfinite(x) for x in q)
 length=f32(math.sqrt(f32(sum(f32(x*x) for x in q))))
 assert length>0
 return [f32(x/length) for x in q]

def applied_reference(plan,clip,prop,time):
 raw=reference(plan,clip,prop,time)
 return normalized(raw) if prop=='rotation' else raw
