extends RefCounted
## Explicit provisional, original procedural silhouettes. NOT mature/approved art.
## Receives only sanitized observed records. No authority/targets or damage writes.
const UNIT_KINDS=["cavalry","siege"]
static func _material(color: Color,name: String="") -> StandardMaterial3D:
	var result=StandardMaterial3D.new(); result.albedo_color=color; result.roughness=1.0; result.resource_name=name
	return result

static func _box(parent: Node3D,pos: Vector3,size: Vector3,color: Color,name: String="") -> MeshInstance3D:
	var mesh=BoxMesh.new(); mesh.size=size; mesh.material=_material(color,name)
	var instance=MeshInstance3D.new(); instance.mesh=mesh; instance.position=pos; parent.add_child(instance)
	return instance

static func _cylinder(parent: Node3D,pos: Vector3,radius: float,height: float,color: Color,sides: int=10) -> MeshInstance3D:
	var mesh=CylinderMesh.new(); mesh.top_radius=radius; mesh.bottom_radius=radius; mesh.height=height; mesh.radial_segments=sides; mesh.material=_material(color,"oak")
	var instance=MeshInstance3D.new(); instance.mesh=mesh; instance.position=pos; parent.add_child(instance)
	return instance

# Low-poly anatomical mount; equipment remains bound to the existing rider rig.
static func _ellipsoid(parent: Node3D,pos: Vector3,size: Vector3,color: Color,name: String) -> MeshInstance3D:
	var mesh=SphereMesh.new();mesh.radius=0.5;mesh.height=1.0;mesh.radial_segments=12;mesh.rings=6;mesh.material=_material(color)
	var part=MeshInstance3D.new();part.mesh=mesh;part.position=pos;part.scale=size;part.name=name;parent.add_child(part)
	return part

static func _horse(root: Node3D,team: Color) -> void:
	var coat=Color("80543b");var dark=Color("312924");var hoof=Color("27282a")
	_ellipsoid(root,Vector3(0,0.68,0.02),Vector3(0.43,0.44,0.88),coat,"HorseBody")
	_ellipsoid(root,Vector3(0,0.73,-0.27),Vector3(0.38,0.46,0.34),coat,"Shoulder")
	var neck=_ellipsoid(root,Vector3(0,0.94,-0.34),Vector3(0.24,0.62,0.30),coat,"Neck");neck.rotation.x=-0.37
	var head=_ellipsoid(root,Vector3(0,1.15,-0.52),Vector3(0.23,0.28,0.39),coat,"HorseHead");head.rotation.x=-0.32
	_ellipsoid(root,Vector3(0,1.06,-0.70),Vector3(0.22,0.17,0.22),Color("a57c60"),"Muzzle")
	for side in [-1,1]:
		var ear=_ellipsoid(root,Vector3(side*0.072,1.32,-0.46),Vector3(0.065,0.19,0.09),coat,"Ear_%d" % side);ear.rotation.z=-side*0.18
		_ellipsoid(root,Vector3(side*0.112,1.19,-0.57),Vector3(0.025,0.032,0.035),dark,"Eye_%d" % side)
		for end in [-1,1]:
			var leg=Node3D.new();root.add_child(leg);leg.position=Vector3(side*0.145,0.64,end*0.28);leg.name="Leg_%d_%d" % [side,end]
			_limb(leg,Vector3.ZERO,Vector3(0,-0.29,0.025*end),0.055,coat)
			_limb(leg,Vector3(0,-0.29,0.025*end),Vector3(0,-0.54,-0.015),0.032,coat)
			_ellipsoid(leg,Vector3(0,-0.575,-0.035),Vector3(0.105,0.105,0.14),hoof,"Hoof")
	for i in 5:
		_ellipsoid(root,Vector3(0,0.88+i*0.075,-0.22-i*0.035),Vector3(0.10,0.15,0.11),dark,"Mane_%d" % i)
	var tail=_ellipsoid(root,Vector3(0,0.45,0.46),Vector3(0.12,0.52,0.15),dark,"Tail");tail.rotation.x=-0.28
	_ellipsoid(root,Vector3(0,0.87,0.05),Vector3(0.47,0.10,0.49),team,"Saddlecloth")
	_ellipsoid(root,Vector3(0,0.92,0.055),Vector3(0.29,0.10,0.32),dark,"Saddle")

# Rider limbs and equipment share rigid local frames. The lance shaft passes
# through the hand origin; no root-space decorative weapon may float beside it.
static func _limb(parent: Node3D,start: Vector3,finish: Vector3,radius: float,color: Color) -> MeshInstance3D:
	var part=_cylinder(parent,(start+finish)*0.5,radius,start.distance_to(finish),color,8)
	part.quaternion=Quaternion(Vector3.UP,(finish-start).normalized())
	return part

static func _rider_armour(root: Node3D,team: Color,metal: Color) -> void:
	var leather=Color("493b32");var trim=Color("b5b3a1")
	var rider=Node3D.new();rider.name="RiderArmour";root.add_child(rider)
	_ellipsoid(rider,Vector3(0,1.16,0.04),Vector3(0.32,0.45,0.26),team,"Tabard")
	_ellipsoid(rider,Vector3(0,1.20,-0.065),Vector3(0.28,0.30,0.10),metal,"Breastplate")
	_box(rider,Vector3(0,1.02,-0.015),Vector3(0.31,0.055,0.26),leather).name="Belt"
	_box(rider,Vector3(0,1.02,-0.15),Vector3(0.065,0.065,0.022),trim).name="Buckle"
	for side in [-1,1]:
		_ellipsoid(rider,Vector3(side*0.18,1.31,0.04),Vector3(0.20,0.14,0.22),metal,"Pauldron_%d" % side)
		var skirt=_box(rider,Vector3(side*0.11,0.96,-0.03),Vector3(0.14,0.20,0.21),team);skirt.rotation.z=side*0.18;skirt.name="TabardSkirt_%d" % side
	_ellipsoid(rider,Vector3(0,1.47,0.035),Vector3(0.25,0.30,0.24),Color("c49b78"),"Face")
	_ellipsoid(rider,Vector3(0,1.56,0.055),Vector3(0.30,0.23,0.29),metal,"HelmetDome")
	_box(rider,Vector3(0,1.51,-0.103),Vector3(0.26,0.055,0.045),trim).name="Brow"
	_box(rider,Vector3(0,1.455,-0.099),Vector3(0.22,0.025,0.025),Color("252b30")).name="EyeSlit"
	_box(rider,Vector3(0,1.435,-0.122),Vector3(0.035,0.14,0.035),metal).name="NoseGuard"
	for side in [-1,1]:
		var cheek=_box(rider,Vector3(side*0.105,1.43,-0.055),Vector3(0.065,0.17,0.12),metal);cheek.rotation.z=-side*0.13;cheek.name="CheekGuard_%d" % side
	_ellipsoid(rider,Vector3(0,1.68,0.065),Vector3(0.085,0.16,0.24),team,"Crest")

static func _rider_equipment(root: Node3D,team: Color,wood: Color,metal: Color):
	var leather=Color("493b32")
	for side in [-1,1]:
		_limb(root,Vector3(side*0.09,1.02,0.04),Vector3(side*0.24,0.83,0.08),0.065,team)
		_limb(root,Vector3(side*0.24,0.83,0.08),Vector3(side*0.25,0.60,0.02),0.055,leather)
		_box(root,Vector3(side*0.25,0.58,-0.035),Vector3(0.12,0.09,0.22),leather)
	var arm=Node3D.new();arm.name="LanceArm";root.add_child(arm);arm.position=Vector3(0.14,1.30,0.04)
	var elbow=Vector3(0.12,-0.12,-0.04);var grip=Vector3(0.12,-0.19,-0.23)
	_limb(arm,Vector3.ZERO,elbow,0.065,team)
	_limb(arm,elbow,grip,0.05,leather)
	var hand=Node3D.new();hand.name="Grip";arm.add_child(hand);hand.position=grip
	_box(hand,Vector3.ZERO,Vector3(0.105,0.10,0.12),leather).name="Glove"
	var weapon=Node3D.new();weapon.name="Lance";hand.add_child(weapon)
	var shaft=_cylinder(weapon,Vector3(0,0,-0.30),0.023,1.50,wood,8);shaft.rotation.x=-PI/2;shaft.name="Shaft"
	var point=_cylinder(weapon,Vector3(0,0,-1.175),0.065,0.25,metal,8);point.mesh.top_radius=0.0;point.rotation.x=-PI/2;point.name="Point"
	var shield_arm=Node3D.new();shield_arm.name="ShieldArm";root.add_child(shield_arm);shield_arm.position=Vector3(-0.14,1.30,0.04)
	var left_elbow=Vector3(-0.10,-0.13,0);var left_grip=Vector3(-0.10,-0.17,-0.18)
	_limb(shield_arm,Vector3.ZERO,left_elbow,0.065,team);_limb(shield_arm,left_elbow,left_grip,0.05,leather)
	var left_hand=Node3D.new();left_hand.name="Grip";shield_arm.add_child(left_hand);left_hand.position=left_grip
	_box(left_hand,Vector3.ZERO,Vector3(0.10,0.10,0.12),leather).name="Glove"
	var shield=_cylinder(left_hand,Vector3(-0.055,0,0),0.25,0.055,metal,12);shield.rotation.z=PI/2;shield.name="Shield"
	var face=_cylinder(left_hand,Vector3(-0.087,0,0),0.215,0.012,team,12);face.rotation.z=PI/2

static func build(parent: Node3D,kind: String,team: Color) -> Node3D:
	var root=Node3D.new(); root.name="ProgressionCandidate"; root.set_meta("provisional_art",true); parent.add_child(root)
	var wood=Color("654b35"); var stone=Color("9b9b8e"); var metal=Color("535e65")
	match kind:
		"stone","iron":
			for i in 4:
				var rock=_box(root,Vector3((i%2)*0.42-0.21,0.3+(i%2)*0.1,(i/2)*0.38-0.2),Vector3(0.5,0.55,0.48),stone if kind=="stone" else metal,"stone")
				rock.rotation.y=i*0.7; rock.rotation.z=(i-1)*0.12
			if kind=="iron":
				for i in 3: _box(root,Vector3(-0.3+i*0.3,0.64,0),Vector3(0.12,0.07,0.42),Color("b68c66"))
		"farm":
			_box(root,Vector3(0,0.06,0),Vector3(2.6,0.12,2.6),Color("70513b"),"stone")
			for x in 6:
				_box(root,Vector3(-1.05+x*0.42,0.14,0),Vector3(0.22,0.12,2.3),Color("4d3d2d"),"oak")
				for z in 5: _box(root,Vector3(-1.05+x*0.42,0.36,-0.85+z*0.42),Vector3(0.09,0.4,0.1),Color("ccbb70"))
		"tower":
			_box(root,Vector3(0,1.4,0),Vector3(1.4,2.8,1.4),stone,"stone")
			_box(root,Vector3(0,2.8,0),Vector3(1.8,0.2,1.8),wood,"oak")
			for x in [-1,1]:
				for z in [-1,1]: _box(root,Vector3(x*0.67,3.1,z*0.67),Vector3(0.4,0.5,0.4),stone,"stone")
			_box(root,Vector3(0,2.4,-0.72),Vector3(0.2,0.6,0.03),Color("252b2c"))
			_box(root,Vector3(0,1.5,-0.73),Vector3(0.5,0.7,0.04),team)
		"stable","workshop":
			_box(root,Vector3(0,0.12,0),Vector3(2.6,0.24,2.6),stone,"stone")
			for x in [-1,1]:
				for z in [-1,1]: _box(root,Vector3(x*1.1,1.1,z*1.1),Vector3(0.2,2.0,0.2),wood,"oak")
			_box(root,Vector3(0,1.0,1.12),Vector3(2.4,1.8,0.15),Color("bcac85"),"stone")
			for x in [-1,1]:
				var roof=_box(root,Vector3(x*0.62,2.15,0),Vector3(1.5,0.16,2.8),team)
				roof.rotation.z=-x*0.3
			if kind=="stable":
				for x in [-1,0,1]:
					_box(root,Vector3(x*0.7,0.6,-0.8),Vector3(0.5,0.9,0.2),wood,"oak")
				_box(root,Vector3(0,1.8,-1.27),Vector3(0.7,0.45,0.1),Color("d0bd86"))
			else:
				_box(root,Vector3(0.75,1.5,0.7),Vector3(0.55,3.0,0.55),stone,"stone")
				_box(root,Vector3(-0.45,0.55,-0.2),Vector3(1.3,0.2,0.65),wood,"oak")
				_box(root,Vector3(-0.45,0.8,-0.2),Vector3(0.55,0.3,0.45),metal)
		"cavalry":
			_horse(root,team)
			_rider_armour(root,team,metal)
			_rider_equipment(root,team,wood,metal)
		"siege":
			_box(root,Vector3(0,0.5,0),Vector3(0.8,0.14,0.92),wood,"oak")
			for z in [-1,1]:
				var axle=_cylinder(root,Vector3(0,0.29,z*0.33),0.055,1.0,metal);axle.rotation.z=PI/2
			for x in [-1,1]:
				for z in [-1,1]:
					var wheel=Node3D.new();root.add_child(wheel);wheel.position=Vector3(x*0.46,0.29,z*0.33);wheel.name="Wheel_%d_%d" % [x,z]
					var rim_mesh=TorusMesh.new();rim_mesh.inner_radius=0.19;rim_mesh.outer_radius=0.25;rim_mesh.rings=16;rim_mesh.ring_segments=6;rim_mesh.material=_material(wood)
					var rim=MeshInstance3D.new();rim.mesh=rim_mesh;wheel.add_child(rim);rim.rotation.z=PI/2;rim.name="Rim"
					var hub=_cylinder(wheel,Vector3.ZERO,0.07,0.13,metal);hub.rotation.z=PI/2;hub.name="Hub"
					for spoke_index in 6:
						var angle=spoke_index*TAU/6
						_limb(wheel,Vector3.ZERO,Vector3(0,cos(angle)*0.22,sin(angle)*0.22),0.025,wood).name="Spoke_%d" % spoke_index
			for x in [-1,1]:
				for z in [-1,1]:_box(root,Vector3(x*0.3,0.90,z*0.34),Vector3(0.09,0.72,0.09),wood,"oak")
			var ram=Node3D.new();root.add_child(ram);ram.name="Ram";ram.position=Vector3(0,0.8,-0.1)
			var shaft=_cylinder(ram,Vector3.ZERO,0.13,1.0,wood);shaft.rotation.x=PI/2;shaft.name="Shaft"
			_box(ram,Vector3(0,0,-0.51),Vector3(0.3,0.3,0.12),metal).name="Head"
			for side in [-1,1]:
				var roof=_box(root,Vector3(side*0.225,1.30,0),Vector3(0.51,0.065,1.08),team);roof.rotation.z=-side*0.34;roof.name="Roof_%d" % side
			_box(root,Vector3(0,1.39,0),Vector3(0.07,0.07,1.12),metal).name="Ridge"

	return root

static func present(record: Dictionary,body: Node3D,color: Color,delta: float,running: bool) -> void:
	if record.get("remembered",false) or record.kind not in UNIT_KINDS: return
	var root=body.get_node_or_null("ProgressionCandidate") as Node3D
	if root==null: root=build(body,record.kind,color)
	var phase=float(root.get_meta("phase",0.0))
	if running and record.get("visual_moving",false): phase+=delta*7.0
	root.set_meta("phase",phase)
	for child in root.get_children():
		if str(child.name).begins_with("Leg_"):
			child.rotation.x=sin(phase+(0 if str(child.name) in ["Leg_-1_-1","Leg_1_1"] else PI))*0.4 if record.get("visual_moving",false) else 0.0
		elif str(child.name).begins_with("Wheel_"): child.rotation.x=phase
	var tick=int(record.get("visual_attack_tick",-1))
	if tick>=0 and tick!=root.get_meta("attack_tick",-1): root.set_meta("attack_tick",tick); root.set_meta("attack_age",0.0)
	var age=float(root.get_meta("attack_age",1.0))
	if running: age+=delta
	root.set_meta("attack_age",age)
	var lance_arm=root.get_node_or_null("LanceArm") as Node3D
	if lance_arm!=null: lance_arm.rotation.x=-sin(age*PI/0.35)*0.30 if age<0.35 else 0.0
	var ram=root.get_node_or_null("Ram") as Node3D
	if ram!=null: ram.position.z=-0.1-(sin(age*PI/0.25)*0.15 if age<0.25 else 0.0)
