#!/usr/bin/env python3
"""HOSTED BLENDER ONLY: assemble/retarget vetted CC0 inputs into original RTS units.
This is a prototype authoring recipe. Asset acceptance requires reopened deformation
checks plus real Godot contact/texture/silhouette review. Never installs into live.
"""
import argparse, hashlib, json, math, re, sys
from pathlib import Path
import bpy, bmesh
from mathutils import Matrix, Quaternion, Vector
KINDS=('villager','spearman','archer','scout')
KEEP=['root','pelvis','spine_01','spine_02','spine_03','neck_01','Head','clavicle_l','upperarm_l','lowerarm_l','hand_l','clavicle_r','upperarm_r','lowerarm_r','hand_r','thigh_l','calf_l','foot_l','ball_l','thigh_r','calf_r','foot_r','ball_r']
KAY={'root':'root','pelvis':'hips','spine_01':'spine','spine_02':'spine','spine_03':'chest','neck_01':'head','Head':'head','upperarm_l':'upperarm.l','lowerarm_l':'lowerarm.l','hand_l':'hand.l','upperarm_r':'upperarm.r','lowerarm_r':'lowerarm.r','hand_r':'hand.r','thigh_l':'upperleg.l','calf_l':'lowerleg.l','foot_l':'foot.l','ball_l':'toes.l','thigh_r':'upperleg.r','calf_r':'lowerleg.r','foot_r':'foot.r','ball_r':'toes.r'}
DURATION={'idle':2.4,'walk':.85,'carry_walk':1.0,'gather_wood':1.3,'gather_food':1.6,'build':1.1,'repair':1.4,'attack':1.0,'hit':.40,'death':1.5}
PROPS={'villager':['axe','hammer','sickle'],'spearman':['spear','shield'],'archer':['bow'],'scout':['sword']}
FPS=24

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def import_gltf(path):
    before=set(bpy.data.objects); actions=set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=str(path),disable_bone_shape=True)
    objects=sorted(set(bpy.data.objects)-before,key=lambda o:o.name)
    rigs=[o for o in objects if o.type=='ARMATURE']
    return objects,rigs,sorted(set(bpy.data.actions)-actions,key=lambda a:a.name)

def activate(obj):
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj

def remove_objects(objects):
    for o in objects:
        if o.name in bpy.data.objects:bpy.data.objects.remove(o,do_unlink=True)

def verify_inputs(root,expected_sha):
    manifest_path=root/'input-manifest.json'
    assert sha(manifest_path)==expected_sha,'Unexpected input manifest bytes'
    manifest=json.loads(manifest_path.read_text())
    expected=set(manifest['files'])|{'input-manifest.json'}
    actual=set()
    for file in root.rglob('*'):
        assert not file.is_symlink(),'Symlink input forbidden'
        if file.is_file():actual.add(file.relative_to(root).as_posix())
    assert actual==expected,{'missing':sorted(expected-actual),'unexpected':sorted(actual-expected)}
    for name,entry in manifest['files'].items():
        file=root/name
        assert file.resolve().is_relative_to(root) and sha(file)==entry['sha256'],name
        assert entry.get('source_url','').startswith('https://')
        if file.suffix=='.gltf':
            document=json.loads(file.read_text())
            for reference in document.get('buffers',[])+document.get('images',[]):
                uri=reference.get('uri','')
                assert uri and Path(uri).name==uri and not ':' in uri,'Only closed local GLTF dependencies allowed'
                assert (file.parent/uri).is_file(),uri
    return manifest

def normalize_weights(mesh):
    # Keep at most four normalized influences per vertex after topology reduction.
    for vertex in mesh.data.vertices:
        pairs=sorted([(g.group,g.weight) for g in vertex.groups if g.weight>1e-7],key=lambda p:(-p[1],p[0]))[:4]
        assert pairs,mesh.name+' unweighted vertex '+str(vertex.index)
        total=sum(w for _,w in pairs)
        for group in mesh.vertex_groups:group.remove([vertex.index])
        for index,weight in pairs:mesh.vertex_groups[index].add([vertex.index],weight/total,'REPLACE')

def normalize_mesh(o,rig):
    world=o.matrix_world.copy();o.parent=None;o.matrix_world=world;activate(o)
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    for mod in list(o.modifiers):o.modifiers.remove(mod)
    o.parent=rig
    mod=o.modifiers.new('Licensed retargeted skin','ARMATURE');mod.object=rig

def trim_head(mesh):
    groups={g.index for g in mesh.vertex_groups if g.name in ['Head','neck_01']}
    keep={v.index for v in mesh.data.vertices if sum(g.weight for g in v.groups if g.group in groups)>.14}
    bm=bmesh.new();bm.from_mesh(mesh.data);bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.index not in keep],context='VERTS')
    bm.to_mesh(mesh.data);bm.free();mesh.data.update()

def merge_finger_weights(mesh):
    groups={g.name:g for g in mesh.vertex_groups}
    for v in mesh.data.vertices:
        contributions={}
        for membership in v.groups:
            name=mesh.vertex_groups[membership.group].name
            target=name
            if name not in KEEP:
                if name.endswith('_l'):target='hand_l' if any(x in name for x in ['index','middle','ring','pinky','thumb']) else 'ball_l'
                elif name.endswith('_r'):target='hand_r' if any(x in name for x in ['index','middle','ring','pinky','thumb']) else 'ball_r'
                else:target='pelvis'
            contributions[target]=contributions.get(target,0)+membership.weight
        for name,weight in contributions.items():
            group=groups.get(name)
            if group is None:group=mesh.vertex_groups.new(name=name);groups[name]=group
            group.add([v.index],min(1,weight),'REPLACE')
    for group in list(mesh.vertex_groups):
        if group.name not in KEEP:mesh.vertex_groups.remove(group)

def reduce_mesh(mesh,budget):
    mesh.data.calc_loop_triangles();before=len(mesh.data.loop_triangles)
    if before>budget:
        activate(mesh)
        # Decimate rest geometry before armature evaluation; keep deformation weights.
        for mod in mesh.modifiers:mod.show_viewport=False
        mod=mesh.modifiers.new('Mobile LOD rest topology','DECIMATE');mod.ratio=budget/before;mod.use_collapse_triangulate=True
        bpy.ops.object.modifier_apply(modifier=mod.name)
        for mod in mesh.modifiers:mod.show_viewport=True
    mesh.data.calc_loop_triangles()
    return {'source_triangles':before,'mobile_triangles':len(mesh.data.loop_triangles)}

def resolve_base_color(material):
    # Imported glTF COLOR_0 creates image * vertex color, not a direct image link.
    # Only the reviewed opaque white-factor graph is accepted; never guess a slot.
    assert material and material.use_nodes,'Missing source node material'
    principled=[n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED']
    assert len(principled)==1,'Ambiguous source BSDF'
    socket=principled[0].inputs['Base Color']
    assert len(socket.links)==1,'Missing source base-color link'
    node=socket.links[0].from_node
    color_layer=None
    if node.type=='MIX':
        assert node.data_type=='RGBA' and node.blend_type=='MULTIPLY' and not node.inputs[0].is_linked and abs(node.inputs[0].default_value-1)<1e-7,'Unsupported source color mix'
        assert len(node.inputs[6].links)==len(node.inputs[7].links)==1,'Incomplete image/color mix'
        image_node=node.inputs[6].links[0].from_node
        color_node=node.inputs[7].links[0].from_node
        assert image_node.type=='TEX_IMAGE' and color_node.type=='VERTEX_COLOR','Unexpected glTF color chain'
        color_layer=color_node.layer_name # Empty means render_color_index, never COLOR_1.
        node=image_node
    assert node.type=='TEX_IMAGE' and node.image and node.extension=='REPEAT','Missing/unsupported source color image'
    vector=node.inputs['Vector']
    uv_name=None
    if vector.is_linked:
        assert len(vector.links)==1 and vector.links[0].from_node.type=='UVMAP','Unsupported source UV transform'
        uv_name=vector.links[0].from_node.uv_map
    return node.image,color_layer,uv_name


def atlas_uv_domain(points):
    assert points and all(math.isfinite(v) for p in points for v in p),'Invalid source UV'
    minimum=[min(p[a] for p in points) for a in range(2)]
    maximum=[max(p[a] for p in points) for a in range(2)]
    low=[math.floor(v) for v in minimum]
    high=[max(low[a]+1,math.ceil(maximum[a])) for a in range(2)]
    span=[high[a]-low[a] for a in range(2)]
    assert all(1<=n<=3 for n in span),'Unexpected tiled UV extent'
    return minimum,maximum,low,span


def atlas_uv_point(point,transform):
    low,span,origin,size=transform
    return tuple((point[a]-low[a])/span[a]*size[a]/1024+origin[a]/1024 for a in range(2))


def atlas_material(meshes,kind,out,src):
    bindings=[];sources={}
    for mesh in meshes:
        assert mesh.data.uv_layers,'Missing source UV'
        render_uv=[layer for layer in mesh.data.uv_layers if layer.active_render]
        assert len(render_uv)==1,'Ambiguous source render UV'
        for index,material in enumerate(mesh.data.materials):
            polygons=[p for p in mesh.data.polygons if p.material_index==index]
            if not polygons:continue
            image,color_name,uv_name=resolve_base_color(material)
            uv=mesh.data.uv_layers.get(uv_name) if uv_name else render_uv[0]
            assert uv is not None,'Source material UV missing'
            if color_name is not None:
                attr=mesh.data.color_attributes.get(color_name) if color_name else mesh.data.color_attributes[mesh.data.color_attributes.render_color_index]
                assert attr is not None and attr.domain in ['POINT','CORNER'],'Rendered COLOR_0 missing'
                for poly in polygons:
                    for li in poly.loop_indices:
                        ci=li if attr.domain=='CORNER' else mesh.data.loops[li].vertex_index
                        assert all(abs(v-1)<1e-6 for v in attr.data[ci].color),'Nonwhite rendered COLOR_0 needs explicit preservation'
            path=Path(bpy.path.abspath(image.filepath)).resolve()
            assert path.is_relative_to(src) and path.is_file(),'Unbound base-color source'
            key=sha(path);relative=path.relative_to(src).as_posix()
            coordinates={li:tuple(uv.data[li].uv) for poly in polygons for li in poly.loop_indices}
            assert coordinates and all(math.isfinite(v) for xy in coordinates.values() for v in xy),'Invalid source UV'
            source=sources.setdefault(key,{'image':image,'path':relative,'uv':[]})
            source['uv'].extend(coordinates.values())
            bindings.append({'mesh':mesh,'material':material.name,'key':key,'coordinates':coordinates,'polygons':len(polygons),'uv_layer':uv.name,'rendered_color':'white COLOR_0' if color_name is not None else 'none'})
    expected_outfit='T_Peasant_BaseColor.png' if kind in ['villager','spearman'] else 'T_Ranger_BaseColor.png'
    assert len(sources)==5,'Expected outfit, arm skin, head skin, eyes and hair textures'
    ordered=sorted(sources,key=lambda key:(Path(sources[key]['path']).name!=expected_outfit,sources[key]['path']))
    assert Path(sources[ordered[0]]['path']).name==expected_outfit,'Primary outfit texture missing'
    atlas=bpy.data.images.new(kind+'_mobile_atlas',width=1024,height=1024,alpha=False)
    pixels=[1.0]*(1024*1024*4);audit_sources=[]
    for index,key in enumerate(ordered):
        source=sources[key];image=source['image'];points=source['uv']
        minimum,maximum,low,span=atlas_uv_domain(points)
        size=512 if index==0 else 256
        ox,oy=(0,0) if index==0 else (512+((index-1)%2)*256,((index-1)//2)*256)
        gutter=4;tw=(size-2*gutter)//span[0];th=(size-2*gutter)//span[1]
        iw,ih=tw*span[0],th*span[1]
        # Repeat an entire affine UV rectangle, including seam-crossing triangles.
        # Never clamp or modulo per vertex. Gutter also repeats the source edge.
        copy=image.copy();copy.scale(tw,th);data=list(copy.pixels)
        for y in range(size):
            sy=(y-gutter)%th
            for x in range(size):
                sx=(x-gutter)%tw;si=(sy*tw+sx)*4;di=((oy+y)*1024+ox+x)*4
                pixels[di:di+4]=data[si:si+4]
        bpy.data.images.remove(copy)
        source['transform']=(low,span,(ox+gutter,oy+gutter),(iw,ih))
        audit_sources.append({'source':source['path'],'sha256':key,'uv_min':minimum,'uv_max':maximum,'tile_low':low,'tile_span':span,'pixel_rect':[ox+gutter,oy+gutter,iw,ih],'gutter_pixels':gutter})
    # The prop white swatch is in unused upper-left atlas space, not the outfit.
    atlas.pixels=pixels;atlas.filepath_raw=str(out/(kind+'_atlas.png'));atlas.file_format='PNG';atlas.save();atlas.pack()
    mat=bpy.data.materials.new('field_textured');mat.use_nodes=True
    p=mat.node_tree.nodes.get('Principled BSDF');p.inputs['Roughness'].default_value=.92;p.inputs['Specular IOR Level'].default_value=.14
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=atlas
    uv_node=mat.node_tree.nodes.new('ShaderNodeUVMap');uv_node.uv_map='FieldUV';mat.node_tree.links.new(uv_node.outputs['UV'],tex.inputs['Vector'])
    colors=mat.node_tree.nodes.new('ShaderNodeVertexColor');colors.layer_name='FieldColor'
    mix=mat.node_tree.nodes.new('ShaderNodeMix');mix.data_type='RGBA';mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1
    mat.node_tree.links.new(tex.outputs['Color'],mix.inputs[6]);mat.node_tree.links.new(colors.outputs['Color'],mix.inputs[7]);mat.node_tree.links.new(mix.outputs[2],p.inputs['Base Color'])
    audit_bindings=[]
    for mesh in meshes:
        assert mesh.data.uv_layers.get('FieldUV') is None,'Unexpected preexisting atlas UV'
        mesh.data.uv_layers.new(name='FieldUV')
        mesh.data.color_attributes.get('FieldColor') or mesh.data.color_attributes.new(name='FieldColor',type='FLOAT_COLOR',domain='CORNER')
        # Allocate every CustomData layer before retaining any RNA handle.
        uv=mesh.data.uv_layers['FieldUV'];attr=mesh.data.color_attributes['FieldColor']
        uv.active_render=True;mesh.data.uv_layers.active_index=len(mesh.data.uv_layers)-1
        for item in attr.data:item.color=(1,1,1,1)
        for binding in [b for b in bindings if b['mesh']==mesh]:
            low,span,origin,size=sources[binding['key']]['transform']
            for li,point in binding['coordinates'].items():
                uv.data[li].uv=atlas_uv_point(point,(low,span,origin,size))
            audit_bindings.append({'mesh':mesh.name,'material':binding['material'],'source_sha256':binding['key'],'source_uv_layer':binding['uv_layer'],'rendered_color':binding['rendered_color'],'polygons':binding['polygons'],'mapped_loops':len(binding['coordinates'])})
        # Export one UV/tint set only: Godot Compatibility consumes TEXCOORD_0.
        # Source UV/color semantics are captured above; originals remain input assets.
        # CustomData removal invalidates cached RNA handles. Keep plain names,
        # then obtain each live handle immediately before the destructive call.
        for layer_name in [layer.name for layer in mesh.data.uv_layers]:
            if layer_name!='FieldUV':mesh.data.uv_layers.remove(mesh.data.uv_layers[layer_name])
        assert [layer.name for layer in mesh.data.uv_layers]==['FieldUV']
        mesh.data.uv_layers.active_index=0;mesh.data.uv_layers[0].active_render=True
        for attribute_name in [attribute.name for attribute in mesh.data.color_attributes]:
            if attribute_name!='FieldColor':mesh.data.color_attributes.remove(mesh.data.color_attributes[attribute_name])
        assert [attribute.name for attribute in mesh.data.color_attributes]==['FieldColor']
        mesh.data.color_attributes.active_color_index=0;mesh.data.color_attributes.render_color_index=0
        # Reacquire after removals and verify every persisted source loop mapping.
        final_uv=mesh.data.uv_layers['FieldUV']
        for binding in [b for b in bindings if b['mesh']==mesh]:
            for li,point in binding['coordinates'].items():
                expected=atlas_uv_point(point,sources[binding['key']]['transform'])
                assert all(abs(final_uv.data[li].uv[a]-expected[a])<1e-6 for a in (0,1)),('Persisted atlas UV mismatch',mesh.name,li)
        for poly in mesh.data.polygons:poly.material_index=0
        mesh.data.materials.clear();mesh.data.materials.append(mat)
    team=bpy.data.materials.new('team_blue');team.use_nodes=True;p=team.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(.058,.11,.15,1);p.inputs['Roughness'].default_value=.94;p.inputs['Specular IOR Level'].default_value=.12
    audit={'atlas_sha256':sha(out/(kind+'_atlas.png')),'size':[1024,1024],'sources':audit_sources,'bindings':audit_bindings,'field_uv':'FieldUV','prop_uv':[.125,.875],'source_graph':'opaque texture times explicitly verified white rendered COLOR_0; no fallback'}
    return (mat,team),audit

def add_prop_geometry(rig,kind,materials):
    result=[]
    def part(name,center,size,bone,color=(.2,.13,.07),team=False,rotation=(0,0,0)):
        bpy.ops.mesh.primitive_cube_add(size=1,location=center);o=bpy.context.object;o.name=name;o.scale=size;o.rotation_euler=rotation;activate(o);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        mod=o.modifiers.new('Soft forged edge','BEVEL');mod.width=.008;mod.segments=1;bpy.ops.object.modifier_apply(modifier=mod.name)
        o.data.materials.append(materials[1 if team else 0]);attr=o.data.color_attributes.new(name='FieldColor',type='FLOAT_COLOR',domain='CORNER')
        for item in attr.data:item.color=(*color,1)
        o.data.uv_layers.active.name='FieldUV'
        for uv in o.data.uv_layers.active.data:uv.uv=(.125,.875)
        g=o.vertex_groups.new(name=bone);g.add(list(range(len(o.data.vertices))),1,'REPLACE');o.parent=rig
        m=o.modifiers.new('Prop skin','ARMATURE');m.object=rig;result.append(o)
        return o
    activate(rig);bpy.ops.object.mode_set(mode='EDIT')
    for prop in PROPS[kind]:
        parent='hand_l' if prop in ['bow','shield'] else 'hand_r'
        bone=rig.data.edit_bones.new('prop_'+prop);bone.head=rig.data.edit_bones[parent].head;bone.tail=bone.head+Vector((0,0,.08));bone.parent=rig.data.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    for prop in PROPS[kind]:
        bone='prop_'+prop;h=rig.data.bones[bone].head_local.copy()
        if prop in ['axe','hammer','sickle','sword','spear']:
            length={'axe':.68,'hammer':.40,'sickle':.35,'sword':.65,'spear':1.9}[prop]
            part(prop+'_haft',h+Vector((0,0,length*.3)),(.035,.035,length),bone)
            if prop=='axe':part('axe_head',h+Vector((.07,0,.49)),(.22,.055,.13),bone,(.25,.28,.27))
            elif prop=='hammer':part('hammer_head',h+Vector((0,0,.29)),(.20,.09,.09),bone,(.2,.22,.22))
            elif prop=='sickle':part('sickle_blade',h+Vector((.07,0,.23)),(.17,.03,.06),bone,(.3,.33,.32))
            elif prop=='sword':part('sword_blade',h+Vector((0,0,.38)),(.055,.025,.51),bone,(.32,.35,.34));part('sword_guard',h+Vector((0,0,.10)),(.17,.05,.04),bone)
            else:part('spear_point',h+Vector((0,0,1.48)),(.065,.03,.23),bone,(.32,.35,.34))
        elif prop=='shield':part('shield',h+Vector((0,-.11,.1)),(.36,.065,.52),bone,(1,1,1),True)
        else:
            for i in range(10):
                t=-math.pi/2+(i+.5)*math.pi/10
                part('bow_limb',h+Vector((0,-.12*math.cos(t),.40*math.sin(t))),(.035,.04,.13),bone,rotation=(-math.atan2(.12*math.sin(t),.40*math.cos(t)),0,0))
                # Rotation is baked around the part center before world translation.
            part('bow_string',h+Vector((0,0,0)),(.006,.006,.80),bone,(.55,.48,.32))
    # One modest team sash, silhouette remains original outfit. It is weighted cloth.
    c=rig.data.bones['spine_03'].head_local.copy()
    part('faction_cloth',c+Vector((0,-.13,-.08)),(.12,.018,.30),'spine_03',(1,1,1),True)
    return result

def action_named(actions,name,rig_name):
    # Blender4.3 appends the exact imported armature object name. Only a
    # numeric datablock collision suffix is optional; semantic variants are not.
    canonical=name+'_'+rig_name
    pattern=re.escape(canonical)+r'(?:\.[0-9]{3,})?'
    matches=[a for a in actions if re.fullmatch(pattern,a.name)]
    assert len(matches)==1,(canonical,[a.name for a in actions]);return matches[0]

def bake_action(dst,source,action,name,duration,kay=False,segments=None):
    dst.animation_data_create();out=bpy.data.actions.new(name);dst.animation_data.action=out
    source.animation_data_create();source.animation_data.action=action
    for tr in source.animation_data.nla_tracks:tr.mute=True
    frames=round(duration*FPS);mapping=KAY if kay else {n:n for n in KEEP}
    for frame in range(frames+1):
        t=frame/frames;current=action;local=t
        if segments:
            for start,end,a in segments:
                if start<=t<=end:current=a;local=(t-start)/(end-start);break
        source.animation_data.action=current
        begin,end=current.frame_range;sample=begin+(end-begin)*local
        bpy.context.scene.frame_set(math.floor(sample),subframe=sample-math.floor(sample))
        # Bake only rotation deltas into the target's own rest proportions. Never
        # transplant source bone lengths or blindly assign incompatible curves.
        world_rotations={}
        for bone in sorted(dst.pose.bones,key=lambda b:len(b.parent_recursive)):
            bone.rotation_mode='QUATERNION';bone.location=(0,0,0);bone.scale=(1,1,1);bone.rotation_quaternion=Quaternion()
            srcname=mapping.get(bone.name)
            if srcname and srcname in source.pose.bones and bone.name!='root':
                src=source.pose.bones[srcname]
                desired=src.matrix.to_quaternion() @ src.bone.matrix_local.to_quaternion().inverted() @ bone.bone.matrix_local.to_quaternion()
                parent_q=world_rotations[bone.parent.name] if bone.parent else Quaternion()
                local_rest=(bone.bone.parent.matrix_local.inverted()@bone.bone.matrix_local).to_quaternion() if bone.parent else bone.bone.matrix_local.to_quaternion()
                bone.rotation_quaternion=local_rest.inverted() @ parent_q.inverted() @ desired
                if bone.name=='pelvis':
                    dz=src.matrix.translation.z-src.bone.matrix_local.translation.z
                    bone.location=bone.bone.matrix_local.to_quaternion().inverted() @ Vector((0,0,dz))
            if bone.name.startswith('prop_') and dst.get('unit_kind')=='villager':
                visible={'gather_wood':'axe','build':'hammer','repair':'hammer','gather_food':'sickle','attack':'axe'}.get(name,'')
                if bone.name!='prop_'+visible:bone.scale=(.001,.001,.001)
            local_rest=(bone.bone.parent.matrix_local.inverted()@bone.bone.matrix_local).to_quaternion() if bone.parent else bone.bone.matrix_local.to_quaternion()
            parent_q=world_rotations[bone.parent.name] if bone.parent else Quaternion()
            world_rotations[bone.name]=parent_q @ local_rest @ bone.rotation_quaternion
            for path in ['rotation_quaternion','location','scale']:bone.keyframe_insert(data_path=path,frame=frame)
    for curve in out.fcurves:
        for point in curve.keyframe_points:point.interpolation='LINEAR'
    out.use_fake_user=True;dst.animation_data.action=None
    return out

def pack_meshes(meshes,rig,kind):
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:o.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join();mesh=bpy.context.object;mesh.name=kind+'_mobile_skin'
    assert len(mesh.data.uv_layers)==1 and mesh.data.uv_layers[0].name=='FieldUV'
    assert len(mesh.data.color_attributes)==1 and mesh.data.color_attributes[0].name=='FieldColor'
    unique=[];remap={}
    for index,mat in enumerate(mesh.data.materials):
        if mat not in unique:unique.append(mat)
        remap[index]=unique.index(mat)
    ids=[remap[p.material_index] for p in mesh.data.polygons];mesh.data.materials.clear()
    for mat in unique:mesh.data.materials.append(mat)
    for p,index in zip(mesh.data.polygons,ids):p.material_index=index
    mesh.data.calc_loop_triangles();assert len(mesh.data.loop_triangles)<=6500,len(mesh.data.loop_triangles)
    assert len(mesh.data.materials)==2
    return mesh

def main():
    p=argparse.ArgumentParser();p.add_argument('--inputs',required=True,type=Path);p.add_argument('--output-root',required=True,type=Path);p.add_argument('--input-manifest-sha256',required=True)
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);src=a.inputs.resolve();out=a.output_root.resolve()
    assert bpy.app.version==(4,3,2),'Pinned Blender4.3.2 required for reviewed action API'
    verified_inputs=verify_inputs(src,a.input_manifest_sha256)
    if out.exists() and any(out.iterdir()):p.error('output must be new or empty')
    art=out/'art/action_characters';glbdir=art/'interchange';glbdir.mkdir(parents=True);(out/'art/.gdignore').touch();reports=out/'reports';reports.mkdir();textures=art/'textures';textures.mkdir()
    manifest={'blender':bpy.app.version_string,'input_manifest_sha256':sha(src/'input-manifest.json'),'license':'CC0 Quaternius and KayKit, original equipment fittings','provenance':verified_inputs['provenance'],'acceptance':'PROTOTYPE NOT VISUALLY ACCEPTED','units':{}}
    for kind in KINDS:
        bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.scene.render.fps=FPS
        folder='peasant' if kind in ['villager','spearman'] else 'ranger';model='Male_Peasant.gltf' if folder=='peasant' else 'Male_Ranger.gltf'
        objects,rigs,_=import_gltf(src/folder/model);assert len(rigs)==1;rig=rigs[0];rig.name='FieldRig';rig['unit_kind']=kind
        meshes=[o for o in objects if o.type=='MESH']
        base_objects,base_rigs,_=import_gltf(src/'base/Superhero_Male_FullBody.gltf')
        for mesh in [o for o in base_objects if o.type=='MESH']:
            if 'SuperHero' in mesh.name or 'Superhero' in mesh.name:trim_head(mesh)
            if len(mesh.data.vertices):meshes.append(mesh)
        hair_objects,hair_rigs,_=import_gltf(src/'hair/Hair_Buzzed.gltf')
        for hair in [o for o in hair_objects if o.type=='MESH']:
            # Free hair is a correctly positioned but unskinned accessory.
            if not len(hair.vertex_groups):
                group=hair.vertex_groups.new(name='Head');group.add(list(range(len(hair.data.vertices))),1.0,'REPLACE')
            meshes.append(hair)
        for mesh in meshes:normalize_mesh(mesh,rig);merge_finger_weights(mesh)
        remove_objects([o for o in base_objects+hair_objects if o.type!='MESH'])
        activate(rig);bpy.ops.object.mode_set(mode='EDIT')
        for bone in list(rig.data.edit_bones):
            if bone.name not in KEEP:rig.data.edit_bones.remove(bone)
        bpy.ops.object.mode_set(mode='OBJECT')
        lod={}
        # Protect head/torso silhouette; decorative boots and bracers get lowest density.
        weights=[]
        for mesh in meshes:
            name=mesh.name.lower()
            weight=.38 if ('boot' in name or 'bracer' in name) else (1.25 if any(x in name for x in ['superhero','body','hood']) else .8)
            mesh.data.calc_loop_triangles();weights.append(max(100,len(mesh.data.loop_triangles)*weight))
        for mesh,weight in zip(meshes,weights):
            lod[mesh.name]=reduce_mesh(mesh,max(60,int(4900*weight/sum(weights))))
            normalize_weights(mesh)
        materials,atlas_audit=atlas_material(meshes,kind,textures,src)
        meshes.extend(add_prop_geometry(rig,kind,materials))
        mesh=pack_meshes(meshes,rig,kind)
        # Load source libraries only after geometry preparation. Delete all source
        # meshes and imported rigs after baked keyframes, never export mannequins.
        libs={};source_objects=[]
        for key,file in [('u1','UAL1_Standard.glb'),('u2','UAL2_Standard.glb'),('range','Rig_Medium_CombatRanged.glb'),('melee','Rig_Medium_CombatMelee.glb'),('tools','Rig_Medium_Tools.glb')]:
            obs,rs,acts=import_gltf(src/'animations'/file);assert len(rs)==1;libs[key]=(rs[0],acts);source_objects+=obs
            for obj in obs:
                if obj.type=='MESH':obj.hide_render=True;obj.hide_viewport=True
        choices={'idle':('u1','Sword_Idle' if kind=='scout' else 'Idle_Loop'),'walk':('u1','Walk_Loop'),'hit':('u1','Hit_Chest'),'death':('u1','Death01')}
        if kind=='villager':choices.update({'carry_walk':('u2','Walk_Carry_Loop'),'gather_wood':('u2','TreeChopping_Loop'),'gather_food':('u2','Farm_Harvest'),'build':('tools','Hammering'),'repair':('u1','Fixing_Kneeling'),'attack':('melee','Melee_1H_Attack_Chop')})
        elif kind=='spearman':choices['attack']=('melee','Melee_2H_Attack_Stab')
        elif kind=='archer':choices['attack']=('range','Ranged_Bow_Draw')
        else:choices['attack']=('u1','Sword_Attack')
        actions={};origins={}
        for name,(key,original) in choices.items():
            source,all_actions=libs[key];action=action_named(all_actions,original,source.name);segments=None
            if kind=='archer' and name=='attack':segments=[(0,.62,action),(.62,1,action_named(all_actions,'Ranged_Bow_Release',source.name))]
            actions[name]=bake_action(rig,source,action,name,DURATION[name],key not in ['u1','u2'],segments)
            origins[name]={'library':key,'source_action':original,'duration_seconds':DURATION[name],'frames':round(DURATION[name]*FPS)+1}
        remove_objects(source_objects)
        for action in list(bpy.data.actions):
            if action not in actions.values():bpy.data.actions.remove(action)
        for name,action in actions.items():
            track=rig.animation_data.nla_tracks.new();track.name=name;track.strips.new(name,0,action);track.mute=True
        rig.animation_data.action=actions['idle'];bpy.context.scene.frame_set(0);rig.animation_data.action=None
        bpy.context.scene.frame_start=0;bpy.context.scene.frame_end=58
        for image in bpy.data.images:
            if image.has_data:image.pack()
        activate(rig);mesh.select_set(True)
        blend=art/(kind+'.blend');bpy.ops.wm.save_as_mainfile(filepath=str(blend))
        glb=glbdir/(kind+'.glb')
        bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_yup=True,export_apply=False,export_animations=True,export_skins=True,export_animation_mode='ACTIONS',export_force_sampling=True,export_frame_range=False,export_anim_slide_to_zero=True,export_rest_position_armature=True)
        weights={g.name:sum(1 for v in mesh.data.vertices for w in v.groups if w.group==g.index and w.weight>0) for g in mesh.vertex_groups}
        manifest['units'][kind]={'source_outfit':folder+'/'+model,'atlas':atlas_audit,'blend_sha256':sha(blend),'glb_sha256':sha(glb),'bones':[b.name for b in rig.data.bones],'weighted_vertices':weights,'armature_modifiers':[m.name for m in mesh.modifiers if m.type=='ARMATURE'],'triangles':len(mesh.data.loop_triangles),'material_surfaces':len(mesh.data.materials),'lod':lod,'clips':origins,'keyed_paths':{n:sorted(set(c.data_path for c in act.fcurves)) for n,act in actions.items()},'root_motion_removed':True}
    import shutil
    shutil.copytree(src/'licenses',art/'licenses');shutil.copy2(src/'input-manifest.json',art/'input-manifest.json')
    (reports/'asset_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print(json.dumps(manifest,indent=2))
if __name__=='__main__':main()
