#!/usr/bin/env python3
"""HOSTED Blender 4.3.2 only. Correct public baked character assets.
No external dependencies, input-manifest, private source recipe, network, or rendering.
The product calibration is anatomical mesh data, not original-source reconstruction.
"""
import argparse,hashlib,json,math,sys
from pathlib import Path
import bpy,bmesh
from mathutils import Matrix,Vector,Quaternion
from mathutils.kdtree import KDTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
import equipment_geometry as equipment
KINDS=('villager','spearman','archer','scout')
PROPS={'villager':['axe','hammer','sickle'],'spearman':['spear','shield'],'archer':['bow'],'scout':['sword']}
SOURCE_SHA={'villager':'8d43a1e693343bcf44f1f00fe138f0a2906ff51b8053f3e80d3b202b173a70db','spearman':'70ad16d2cd92cd239547bcf21e2384acb75cd8b6dea71c11d9cf6ab18025b898','archer':'7456bcb026fbd2045656766fbffcf65aa4c95f15f6aa6e57b621544480a83206','scout':'effca2c4ccece6b815640f449da1786db66d5ec61433447621475b4ba8212e75'}
FPS=24

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def activate(obj):
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj

def basis_y(direction,reference):
    y=Vector(direction).normalized();z=Vector(reference)-y*Vector(reference).dot(y)
    if z.length<1e-6:z=Vector((1,0,0))-y*y.x
    z.normalize();x=y.cross(z).normalized();return Matrix((x,y,z)).transposed()

def grip_rotation(shaft,forward):
    z=Vector(shaft).normalized();y=Vector(forward)-z*Vector(forward).dot(z);assert y.length>1e-6
    y.normalize();x=y.cross(z).normalized();return Matrix((x,y,z)).transposed()

def mat4(rotation,location):
    result=rotation.to_4x4();result.translation=Vector(location);return result

def packed_image_inventory():
    return sorted(hashlib.sha256(bytes(image.packed_file.data)).hexdigest() for image in bpy.data.images)

def verify_loaded_source_is_closed():
    # Fail before any explicit dependency-graph evaluation or frame change.
    assert len(bpy.data.texts)==0,'Embedded text datablocks forbidden'
    assert len(bpy.data.libraries)==0 and len(bpy.data.cache_files)==0,'External linked/cache inputs forbidden'
    assert len(bpy.data.movieclips)==0 and len(bpy.data.sounds)==0,'Unreviewed media dependencies forbidden'
    checked=set();pending=[]
    for prop in bpy.data.bl_rna.properties:
        if prop.type=='COLLECTION':
            for item in getattr(bpy.data,prop.identifier):
                if isinstance(item,bpy.types.ID):pending.append(item)
    while pending:
        item=pending.pop();identity=item.as_pointer()
        if identity in checked:continue
        checked.add(identity)
        assert item.library is None,('Linked ID forbidden',item.name)
        animation=getattr(item,'animation_data',None)
        assert animation is None or len(animation.drivers)==0,('Driver forbidden',item.name)
        node_tree=getattr(item,'node_tree',None)
        if node_tree is not None:pending.append(node_tree)
        shape_keys=getattr(item,'shape_keys',None)
        if shape_keys is not None:pending.append(shape_keys)
    for image in bpy.data.images:
        assert image.source in ('FILE','GENERATED') and image.packed_file is not None,('Unpacked or generated image forbidden',image.name)
    for obj in bpy.data.objects:
        assert obj.type in ('ARMATURE','MESH') and len(obj.constraints)==0,('Unexpected object/constraint',obj.name)
        assert all(mod.type=='ARMATURE' for mod in obj.modifiers),('Unreviewed modifier',obj.name)
        if obj.type=='ARMATURE':
            assert all(len(bone.constraints)==0 for bone in obj.pose.bones),'Unreviewed pose constraint'

def protected_body_signature(mesh,equipped_sides):
    # Preserve all non-equipped-hand body/cloth geometry and weights through joins.
    mutable={'hand_'+side for side in equipped_sides}
    rows=[]
    for vertex in mesh.data.vertices:
        weights=sorted((mesh.vertex_groups[g.group].name,round(g.weight,8)) for g in vertex.groups if g.weight>1e-6)
        if any(name in mutable or name.startswith('prop_') or name.startswith('bow_string_') or name=='nocked_arrow' for name,_ in weights):continue
        rows.append(([round(v,8) for v in vertex.co],weights))
    rows.sort(key=lambda row:json.dumps(row,separators=(',',':')))
    return {'vertices':len(rows),'sha256':hashlib.sha256(json.dumps(rows,separators=(',',':')).encode()).hexdigest()}

def apply_hand_calibration(mesh,rig,hands):
    # Preserve existing body split normals; recompute only deformed hand corners.
    old_normals=[tuple(item.vector)for item in mesh.data.corner_normals]
    assert len(old_normals)==len(mesh.data.loops)
    changed=set();stats={}
    for side,spec in hands.items():
        name='hand_'+side;group=mesh.vertex_groups.get(name);assert group is not None
        rows=spec['vertices'];tree=KDTree(len(rows))
        for index,row in enumerate(rows):tree.insert(Vector(row['rest']),index)
        tree.balance();rest=rig.data.bones[name].matrix_local.copy();inv=rest.inverted();matched=0;errors=[]
        for vertex in mesh.data.vertices:
            weight=sum(g.weight for g in vertex.groups if g.group==group.index)
            if weight<=1e-6:continue
            local=inv@vertex.co;point,index,distance=tree.find(local)
            assert distance<=2e-5,(name,'Current public Blender/GLB rest vertex correspondence failed',distance)
            new_position=rest@Vector(rows[index]['posed'])
            if (new_position-vertex.co).length>1e-7:changed.add(vertex.index)
            vertex.co=new_position;matched+=1;errors.append(distance)
        assert matched>100,(name,'Missing current hand vertices')
        stats[side]={'vertices':matched,'max_current_glb_blend_correspondence_m':max(errors),'grip_to_hand':spec['grip_to_hand']}
    mesh.data.update()
    sums={index:Vector((0,0,0))for index in changed}
    for poly in mesh.data.polygons:
        for index in poly.vertices:
            if index in sums:sums[index]+=poly.normal*poly.area
    for poly in mesh.data.polygons:
        for loop_index in poly.loop_indices:
            vertex=mesh.data.loops[loop_index].vertex_index
            if vertex in changed:
                normal=sums[vertex].normalized() if poly.use_smooth and sums[vertex].length>1e-10 else poly.normal
                old_normals[loop_index]=tuple(normal)
    mesh.data.normals_split_custom_set(old_normals);mesh.data.update()
    return stats

def remove_old_equipment(mesh,rig):
    groups={g.index for g in mesh.vertex_groups if g.name.startswith('prop_')}
    bm=bmesh.new();bm.from_mesh(mesh.data);layer=bm.verts.layers.deform.active
    assert layer is not None
    remove=[v for v in bm.verts if sum(w for g,w in v[layer].items() if g in groups)>.999]
    assert remove,'Missing original rigid equipment'
    bmesh.ops.delete(bm,geom=remove,context='VERTS');bm.to_mesh(mesh.data);bm.free();mesh.data.update()

def configure_prop_bones(rig,kind,hand_frames):
    activate(rig);bpy.ops.object.mode_set(mode='EDIT')
    for prop in PROPS[kind]:
        side='l' if prop in ('bow','shield') else 'r';hand=rig.data.edit_bones['hand_'+side]
        frame=hand.matrix@hand_frames[side];bone=rig.data.edit_bones['prop_'+prop]
        bone.head=frame.translation;bone.tail=frame.translation+frame.to_3x3().col[1]*.08;bone.align_roll(frame.to_3x3().col[2]);bone.parent=hand;bone.use_connect=False
    if kind=='archer':
        frame=rig.data.edit_bones['prop_bow'].matrix.copy()
        for name,z in [('bow_string_upper',.40),('bow_string_lower',-.40)]:
            bone=rig.data.edit_bones.new(name);bone.parent=rig.data.edit_bones['prop_bow']
            bone.head=frame@Vector((0,-.14,z));bone.tail=frame@Vector((0,-.14,.055 if z>0 else -.055));bone.align_roll(frame.to_3x3().col[0])
        bone=rig.data.edit_bones.new('bow_string_contact');bone.parent=rig.data.edit_bones['prop_bow']
        bone.head=frame@Vector((0,-.14,-.055));bone.tail=frame@Vector((0,-.14,.055));bone.align_roll(frame.to_3x3().col[0])
        frame=rig.data.edit_bones['hand_r'].matrix@hand_frames['r'];bone=rig.data.edit_bones.new('nocked_arrow');bone.parent=rig.data.edit_bones['hand_r']
        bone.head=frame.translation;bone.tail=frame.translation+frame.to_3x3().col[1]*.60;bone.align_roll(frame.to_3x3().col[2])
    bpy.ops.object.mode_set(mode='OBJECT')
    for bone in rig.pose.bones:
        bone.rotation_mode='QUATERNION';bone.matrix_basis=Matrix.Identity(4)
    return {b.name:b.matrix_local.copy()for b in rig.data.bones}

def create_equipment_mesh(rig,body,kind,rest):
    vertices=[];faces=[];face_meta=[];groups={}
    def add_piece(piece,bone,frame):
        offset=len(vertices);vertices.extend([tuple(frame@Vector(v))for v in piece['vertices']]);groups.setdefault(bone,[]).extend(range(offset,len(vertices)))
        faces.extend([tuple(offset+i for i in face)for face in piece['faces']]);face_meta.extend([(piece['team'],piece['color'])]*len(piece['faces']))
    for prop in PROPS[kind]:
        name='prop_'+prop
        for piece in equipment.build(prop):add_piece(piece,name,rest[name])
    if kind=='archer':
        frame=rest['prop_bow']
        for name,z in [('bow_string_upper',.40),('bow_string_lower',-.40)]:
            vv,ff=equipment.cylinder((0,-.14,z),(0,-.14,.055 if z>0 else -.055),.003,6)
            add_piece(dict(vertices=vv,faces=ff,team=False,color=(.54,.47,.30,1)),name,frame)
        vv,ff=equipment.cylinder((0,-.14,-.055),(0,-.14,.055),.003,6)
        add_piece(dict(vertices=vv,faces=ff,team=False,color=(.54,.47,.30,1)),'bow_string_contact',frame)
        vv,ff=equipment.cylinder((0,-.035,0),(0,.55,0),.0035,6)
        add_piece(dict(vertices=vv,faces=ff,team=False,color=(.35,.23,.12,1)),'nocked_arrow',rest['nocked_arrow'])
    data=bpy.data.meshes.new(kind+'_calibrated_equipment');data.from_pydata(vertices,[],faces);data.update();obj=bpy.data.objects.new('calibrated_equipment',data);bpy.context.collection.objects.link(obj)
    materials={m.name:m for m in body.data.materials};assert set(materials)=={'field_textured','team_blue'}
    data.materials.append(materials['field_textured']);data.materials.append(materials['team_blue'])
    uv=data.uv_layers.new(name='FieldUV');attr=data.color_attributes.new(name='FieldColor',type='FLOAT_COLOR',domain='CORNER')
    for poly,(team,color) in zip(data.polygons,face_meta):
        poly.material_index=1 if team else 0
        for li in poly.loop_indices:uv.data[li].uv=(.125,.875);attr.data[li].color=color
    for name,indices in groups.items():obj.vertex_groups.new(name=name).add(indices,1.,'REPLACE')
    obj.parent=rig;mod=obj.modifiers.new('Calibrated equipment skin','ARMATURE');mod.object=rig
    activate(body);obj.select_set(True);bpy.ops.object.join();body.data.update()
    # Join can create duplicate material slots. Preserve the exact original two materials.
    unique=[];remap={}
    for i,material in enumerate(body.data.materials):
        if material not in unique:unique.append(material)
        remap[i]=unique.index(material)
    indices=[remap[p.material_index]for p in body.data.polygons];body.data.materials.clear()
    for material in unique:body.data.materials.append(material)
    for poly,index in zip(body.data.polygons,indices):poly.material_index=index
    assert len(unique)==2

def arm_to_grip(rig,side,position,rotation,grip_frame):
    """Two-bone analytic arm IK, measured bone lengths, immutable grip transform."""
    upper=rig.pose.bones['upperarm_'+side];lower=rig.pose.bones['lowerarm_'+side];hand=rig.pose.bones['hand_'+side]
    desired=mat4(rotation,position)@grip_frame.inverted();target=desired.translation
    bpy.context.view_layer.update();shoulder=upper.head.copy();a=upper.bone.length;b=lower.bone.length;delta=target-shoulder;distance=delta.length
    assert distance>abs(a-b)+.002 and distance<a+b-.002,('Unreachable authored wrist',side,distance,a,b)
    direction=delta.normalized();sign=1 if side=='l' else -1
    pole=Vector((sign,0,-.42));pole-=direction*pole.dot(direction);assert pole.length>1e-6;pole.normalize()
    along=(a*a-b*b+distance*distance)/(2*distance);height=math.sqrt(max(0.,a*a-along*along));elbow=shoulder+direction*along+pole*height
    bend_normal=direction.cross(pole).normalized()
    upper_reference=upper.matrix.to_3x3().col[2].copy()
    upper.matrix=mat4(basis_y(elbow-shoulder,upper_reference),shoulder);bpy.context.view_layer.update()
    lower_reference=lower.matrix.to_3x3().col[2].copy()
    lower.matrix=mat4(basis_y(target-elbow,lower_reference),elbow);bpy.context.view_layer.update();hand.matrix=desired;bpy.context.view_layer.update()
    actual=hand.matrix@grip_frame;error=(actual.translation-Vector(position)).length
    assert error<1e-5,('Authored grip target mismatch',error)
    return error

def smooth(x):x=max(0.,min(1.,x));return x*x*(3-2*x)
def blend(a,b,t):return Vector(a).lerp(Vector(b),t)
def stance(rig,kind,clip,t,frames):
    """Authored equipment-aware upper body only; original locomotion/root remain."""
    if kind=='villager' or clip not in ('idle','walk','attack'):return None
    # Body proportions, not prop offsets: positions are relative to animated pelvis.
    pelvis=rig.pose.bones['pelvis'].head.copy();torso=rig.pose.bones['spine_03'].head.copy()
    shoulder_span=(rig.pose.bones['upperarm_l'].head-rig.pose.bones['upperarm_r'].head).length
    side=shoulder_span*.70;waist=pelvis.z+.20;chest=torso.z+.035
    bob=.012*math.sin(t*math.tau) if clip in ('idle','walk') else 0.
    held=grip_rotation((0,0,1),(0,-1,0));draw=None
    if kind=='spearman':
        right=Vector((-side,-.18,waist+bob));left=Vector((side*.88,-.27,chest-.08+bob));rotation=held
        if clip=='attack':
            # One-handed thrust. The shield arm stays in guard, never a second spear grip.
            thrust=smooth(t/.56) if t<=.56 else 1-smooth((t-.56)/.44)
            shoulder=rig.pose.bones['upperarm_r'].head.copy()
            right=shoulder+Vector((-.05,-.14-.15*thrust,-.10+.05*thrust))
            rotation=grip_rotation(blend((0,-.62,.78),(0,-.99,.14),thrust),(0,0,1))
        arm_to_grip(rig,'r',right,rotation,frames['r']);arm_to_grip(rig,'l',left,held,frames['l'])
    elif kind=='archer':
        left=Vector((side*.82,-.21,waist+bob))
        if clip=='attack':
            left=Vector((side*.37,-.34,chest+.04))
            pull=smooth(t/.62) if t<=.62 else 1.
            right=blend((left.x,-.20,left.z),(-side*.30,-.04,chest+.12),pull)
            if t>.62:right.y+=.045*smooth((t-.62)/.16)
            # Arrow direction +Y equipment points toward the target (-Y world).
            arrow_direction=(left-right).normalized()
            arrow_up=Vector((0,0,1))-arrow_direction*arrow_direction.z
            right_rotation=grip_rotation(arrow_up,arrow_direction)
            arm_to_grip(rig,'r',right,right_rotation,frames['r'])
            draw={'right_contact':right,'released':t>.62,'release_return':smooth((t-.62)/.09)}
        arm_to_grip(rig,'l',left,held,frames['l'])
    elif kind=='scout':
        if clip in ('idle','walk'):
            right=Vector((-side,-.20,waist+bob));rotation=grip_rotation((-.12,-.20,.972),(0,-1,0))
            arm_to_grip(rig,'r',right,rotation,frames['r'])
        # Retain the existing one-handed sword attack, now with a real closed grip.
    return draw

def string_pose(rig,clip,t,draw,rest,frames):
    bow=rig.pose.bones['prop_bow'].matrix.copy()
    nock=bow@Matrix.Translation(Vector((0,-.14,0)))
    if draw is not None:
        held=rig.pose.bones['hand_r'].matrix@frames['r']
        if not draw['released']:nock=held
        else:
            amount=draw['release_return']
            nock=mat4(held.to_quaternion().slerp(nock.to_quaternion(),amount).to_matrix(),held.translation.lerp(nock.translation,amount))
    # Keep the actual three-finger holding segment straight through the calibrated
    # hook. The two free branches bend at its ends, rather than abandoning the
    # index/ring fingers by converging immediately on a single nock point.
    lower=nock@Vector((0,0,-.055));upper=nock@Vector((0,0,.055))
    segments=[('bow_string_upper',bow@Vector((0,-.14,.40)),upper,bow.to_3x3().col[0]),
              ('bow_string_lower',bow@Vector((0,-.14,-.40)),lower,bow.to_3x3().col[0]),
              ('bow_string_contact',lower,upper,nock.to_3x3().col[0])]
    for name,start,end,reference in segments:
        direction=end-start;length=direction.length;assert .05<length<1.2
        matrix=mat4(basis_y(direction,reference),start);matrix.col[1]=matrix.col[1]*(length/rig.data.bones[name].length)
        rig.pose.bones[name].matrix=matrix
    arrow=rig.pose.bones['nocked_arrow'];arrow.matrix_basis=Matrix.Identity(4)
    arrow.scale=(1.,1.,1.) if clip=='attack' and t<=.62 else (.001,.001,.001)

def bake_poses(rig,kind,frames,rest):
    originals={a.name:a for a in bpy.data.actions};required=['idle','walk','attack','hit','death']
    if kind=='villager':required+=['carry_walk','gather_wood','gather_food','build','repair']
    assert set(originals)==set(required),('Unexpected public action inventory',list(originals))
    for track in list(rig.animation_data.nla_tracks):rig.animation_data.nla_tracks.remove(track)
    outputs={};samples={}
    for name in required:
        action=originals[name].copy();action.name=name+'__calibrated';rig.animation_data.action=action;begin,end=originals[name].frame_range;assert begin==0 and end<=58
        frames_count=round(end);sample_rows=[]
        for frame in range(frames_count+1):
            bpy.context.scene.frame_set(frame);t=frame/max(1,frames_count)
            for prop in PROPS[kind]:
                bone=rig.pose.bones['prop_'+prop];bone.matrix_basis=Matrix.Identity(4)
                if kind=='villager':
                    visible={'attack':'axe','gather_wood':'axe','gather_food':'sickle','build':'hammer','repair':'hammer'}.get(name,'')
                    bone.scale=(1.,1.,1.) if prop==visible else (.001,.001,.001)
            bpy.context.view_layer.update();draw=stance(rig,kind,name,t,frames)
            if kind=='archer':string_pose(rig,name,t,draw,rest,frames)
            bpy.context.view_layer.update()
            # Full TRS channels retain tool restoration and new string/arrow joints.
            for bone in rig.pose.bones:
                if bone.rotation_mode!='QUATERNION':bone.rotation_mode='QUATERNION'
                for path in ('rotation_quaternion','location','scale'):bone.keyframe_insert(data_path=path,frame=frame)
            if frame in {0,round(frames_count*.25),round(frames_count*.56),round(frames_count*.62),round(frames_count*.75),frames_count}:
                sample_rows.append({'frame':frame,'fraction':t,'grips':{side:[list(row)for row in rig.pose.bones['hand_'+side].matrix@grip]for side,grip in frames.items()}})
        for curve in action.fcurves:
            for point in curve.keyframe_points:point.interpolation='LINEAR'
        action.use_fake_user=True;outputs[name]=action;samples[name]=sample_rows
    rig.animation_data.action=None
    for action in originals.values():bpy.data.actions.remove(action)
    for name,action in outputs.items():
        action.name=name;track=rig.animation_data.nla_tracks.new();track.name=name;track.strips.new(name,0,action);track.mute=True
    return outputs,samples

def main():
    p=argparse.ArgumentParser();p.add_argument('--kind',choices=KINDS,required=True);p.add_argument('--input-root',type=Path,required=True);p.add_argument('--calibration',type=Path,required=True);p.add_argument('--calibration-sha256',required=True);p.add_argument('--output-root',type=Path,required=True)
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);assert bpy.app.version==(4,3,2);assert sha(a.calibration)==a.calibration_sha256
    source=a.input_root/(a.kind+'.blend');assert not source.is_symlink() and sha(source)==SOURCE_SHA[a.kind];out=a.output_root.resolve();assert not out.exists();out.mkdir(parents=True)
    calibration=json.loads(a.calibration.read_text());assert calibration['schema']=='current-product-grip-calibration-v1';spec=calibration['units'][a.kind];hands=spec['hands']
    expected_hands={'l','r'} if a.kind in ('spearman','archer') else {'r'}
    assert set(hands)==expected_hands,'Incomplete or overbroad equipped-hand calibration'
    assert all(value.get('data_contact_checks_passed') is True for value in hands.values()),'Unaccepted or incomplete anatomical/contact calibration'
    if a.kind=='archer':assert hands.get('r',{}).get('contact_kind')=='string_hook','Archer requires measured string-hook calibration, not thick-haft fist'
    bpy.ops.wm.open_mainfile(filepath=str(source.resolve()),load_ui=False,use_scripts=False)
    verify_loaded_source_is_closed()
    packed_before=packed_image_inventory()
    rigs=[o for o in bpy.data.objects if o.type=='ARMATURE'];meshes=[o for o in bpy.data.objects if o.type=='MESH'];assert len(rigs)==len(meshes)==1
    rig=rigs[0];body=meshes[0];assert rig.name=='FieldRig' and body.parent==rig
    assert all(abs(rig.matrix_world[i][j]-(1 if i==j else 0))<1e-6 for i in range(4)for j in range(4))
    assert all(abs(body.matrix_local[i][j]-(1 if i==j else 0))<1e-6 for i in range(4)for j in range(4))
    rig.animation_data.action=None
    for track in rig.animation_data.nla_tracks:track.mute=True
    for bone in rig.pose.bones:bone.matrix_basis=Matrix.Identity(4)
    bpy.context.view_layer.update()
    protected_before=protected_body_signature(body,hands)
    hand_stats=apply_hand_calibration(body,rig,hands);remove_old_equipment(body,rig)
    frames={side:Matrix(value['grip_to_hand'])for side,value in hands.items()};rest=configure_prop_bones(rig,a.kind,frames);create_equipment_mesh(rig,body,a.kind,rest)
    assert protected_body_signature(body,hands)==protected_before,'Non-equipped hand/body/cloth geometry or weights changed'
    actions,samples=bake_poses(rig,a.kind,frames,rest);body.data.calc_loop_triangles()
    assert len(body.data.loop_triangles)<=6500 and len(rig.data.bones)<=32 and len(body.data.materials)==2
    assert len(body.data.uv_layers)==1 and body.data.uv_layers[0].name=='FieldUV';assert len(body.data.color_attributes)==1 and body.data.color_attributes[0].name=='FieldColor'
    bpy.context.scene.render.fps=FPS;rig.animation_data.action=actions['idle'];bpy.context.scene.frame_set(0);rig.animation_data.action=None
    # All original atlas pixels remain packed and unchanged. No image processing.
    assert all(image.source in ('FILE','GENERATED') and image.packed_file is not None for image in bpy.data.images)
    assert packed_image_inventory()==packed_before,'Packed texture data changed'
    activate(rig);body.select_set(True);blend=out/(a.kind+'.blend');glb=out/(a.kind+'.glb')
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),check_existing=False)
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_yup=True,export_apply=False,export_animations=True,export_skins=True,export_animation_mode='ACTIONS',export_force_sampling=True,export_frame_range=False,export_anim_slide_to_zero=True,export_rest_position_armature=True)
    report={'schema':'rts-public-grip-correction-v1','blender':bpy.app.version_string,'script_sha256':sha(__file__),'equipment_script_sha256':sha(Path(__file__).with_name('equipment_geometry.py')),'unit':a.kind,'source_blend_sha256':sha(source),'calibration_sha256':sha(a.calibration),'blend_sha256':sha(blend),'glb_sha256':sha(glb),'bones':[b.name for b in rig.data.bones],'triangles':len(body.data.loop_triangles),'material_surfaces':len(body.data.materials),'protected_body_geometry':protected_before,'packed_images_unchanged':True,'packed_image_count':len(packed_before),'packed_image_inventory_sha256':hashlib.sha256('\n'.join(packed_before).encode()).hexdigest(),'hand_calibration':hand_stats,'pose_samples':samples,'scope':'Authored data only; requires independent GLB/contact and actual rendered acceptance; no game execution or physical-device claim'}
    (out/(a.kind+'-audit.json')).write_text(json.dumps(report,indent=2)+'\n');print('GRIP_AUTHORING_DATA_COMPLETE',a.kind,report['glb_sha256'])
if __name__=='__main__':main()
