#!/usr/bin/env python3
"""Hosted Blender-only reopening probe; never a render/artistic approval."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import bpy

KINDS = ('villager', 'spearman', 'archer', 'scout')
COMMON = {'idle', 'walk', 'attack', 'hit', 'death'}
WORK = {'carry_walk', 'gather_wood', 'gather_food', 'build', 'repair'}
def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--output-root', required=True, type=Path); parser.add_argument('--report', required=True, type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:]); root = args.output_root.resolve()
    assert bpy.app.version == (4,3,2)
    assert not bpy.context.preferences.filepaths.use_scripts_auto_execute
    manifest = json.loads((root/'reports/asset_manifest.json').read_text())
    result = {'scope':'Reopened evaluated geometry only; no contact, render, or art approval', 'blender':bpy.app.version_string, 'units':{}}
    for kind in KINDS:
        path = root/'art/action_characters'/(kind+'.blend')
        assert sha(path) == manifest['units'][kind]['blend_sha256']
        bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False, use_scripts=False)
        assert not bpy.context.preferences.filepaths.use_scripts_auto_execute
        assert not bpy.data.libraries and not any(t.use_module for t in bpy.data.texts)
        for collection in (bpy.data.objects, bpy.data.meshes, bpy.data.materials, bpy.data.shape_keys, bpy.data.worlds, bpy.data.scenes, bpy.data.node_groups):
            assert all(not getattr(d, 'animation_data', None) or not d.animation_data.drivers for d in collection)
        rigs = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE']
        meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
        assert len(rigs) == len(meshes) == 1 and len(bpy.context.scene.objects) == 2
        rig = rigs[0]; mesh = meshes[0]
        assert 20 <= len(rig.data.bones) <= 32
        assert len(mesh.modifiers) == 1 and mesh.modifiers[0].type == 'ARMATURE' and mesh.modifiers[0].object == rig
        assert not rig.constraints and all(not b.constraints for b in rig.pose.bones)
        assert not rig.animation_data.drivers
        mesh.data.calc_loop_triangles(); assert len(mesh.data.loop_triangles) <= 6500 and len(mesh.data.materials) == 2
        for vertex in mesh.data.vertices:
            weights = [(mesh.vertex_groups[g.group].name, g.weight) for g in vertex.groups if g.weight > 1e-7]
            assert 1 <= len(weights) <= 4 and abs(sum(w for _,w in weights)-1) < 1e-5
            assert all(n in rig.data.bones for n,_ in weights)
        expected = COMMON | (WORK if kind == 'villager' else set())
        assert {a.name for a in bpy.data.actions} == expected
        for tr in rig.animation_data.nla_tracks: tr.mute = True
        unit = {'blend_sha256':sha(path), 'clips':{}}
        for name in sorted(expected):
            action = bpy.data.actions[name]; rig.animation_data.action = action
            assert all(c.data_path.startswith('pose.bones[') for c in action.fcurves)
            begin, end = action.frame_range; samples = []; initial = None; max_change = 0
            for fraction in (0, .25, .5, .75, 1):
                frame = begin+(end-begin)*fraction
                bpy.context.scene.frame_set(int(frame), subframe=frame-int(frame)); bpy.context.view_layer.update()
                evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()); evaluated_mesh = evaluated.to_mesh()
                try:
                    coords = [tuple(v.co) for v in evaluated_mesh.vertices]
                    assert all(math.isfinite(x) for p in coords for x in p)
                    assert len(coords) == len(mesh.data.vertices)
                    if initial is None: initial = coords
                    movement = max(sum((a-b)**2 for a,b in zip(x,y))**.5 for x,y in zip(coords,initial))
                    max_change = max(max_change, movement)
                    samples.append({'fraction':fraction, 'vertex_sha256':hashlib.sha256(json.dumps(coords,separators=(',',':')).encode()).hexdigest(), 'bounds':[[min(p[i] for p in coords) for i in range(3)],[max(p[i] for p in coords) for i in range(3)]], 'max_vertex_displacement_from_start':movement})
                finally: evaluated.to_mesh_clear()
                root_bone = rig.pose.bones['root']; assert root_bone.location.length < 1e-5 and root_bone.rotation_quaternion.angle < 1e-5
            assert max_change > 1e-5, (kind, name, 'No evaluated mesh deformation')
            unit['clips'][name] = {'samples':samples, 'max_vertex_displacement':max_change}
        assert sha(path) == manifest['units'][kind]['blend_sha256'], 'Reopen unexpectedly changed source bytes'
        result['units'][kind] = unit
    with args.report.open('x') as f: json.dump(result, f, indent=2); f.write('\n')
    print('REOPENED_BLEND_DEFORMATION_PASS')

if __name__ == '__main__': main()
