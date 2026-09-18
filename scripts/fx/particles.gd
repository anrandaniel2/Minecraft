class_name ParticleFx
extends Node3D

## Shared one-shot particle emitters.
##
## Every effect kind owns a single GPUParticles3D that is moved into place and
## restarted on demand, so spawning particles never allocates nodes. Kinds can
## be disabled as a whole through the graphics settings.

const KINDS: Dictionary = {
	"block_break": {"amount": 14, "lifetime": 0.7, "color": Color(1, 1, 1), "size": 0.14,
		"gravity": Vector3(0, -16, 0), "spread": 55.0, "speed": 4.0},
	"smoke": {"amount": 12, "lifetime": 1.4, "color": Color(0.35, 0.35, 0.38, 0.6), "size": 0.3,
		"gravity": Vector3(0, 1.4, 0), "spread": 30.0, "speed": 1.2},
	"spark": {"amount": 10, "lifetime": 0.5, "color": Color(1.0, 0.85, 0.4), "size": 0.1,
		"gravity": Vector3(0, -10, 0), "spread": 70.0, "speed": 5.0},
	"splash": {"amount": 16, "lifetime": 0.8, "color": Color(0.6, 0.75, 1.0, 0.8), "size": 0.12,
		"gravity": Vector3(0, -14, 0), "spread": 60.0, "speed": 4.5},
	"note": {"amount": 4, "lifetime": 1.0, "color": Color(1.0, 0.6, 0.9), "size": 0.22,
		"gravity": Vector3(0, 3.0, 0), "spread": 20.0, "speed": 1.5},
	"heart": {"amount": 3, "lifetime": 1.2, "color": Color(0.9, 0.3, 0.4), "size": 0.24,
		"gravity": Vector3(0, 2.4, 0), "spread": 18.0, "speed": 1.0},
	"critical": {"amount": 8, "lifetime": 0.5, "color": Color(1.0, 0.9, 0.5), "size": 0.16,
		"gravity": Vector3(0, -6, 0), "spread": 45.0, "speed": 3.0},
	"explosion": {"amount": 40, "lifetime": 1.6, "color": Color(0.45, 0.42, 0.4, 0.85),
		"size": 0.7, "gravity": Vector3(0, -3, 0), "spread": 90.0, "speed": 8.0},
	"portal": {"amount": 20, "lifetime": 1.4, "color": Color(0.6, 0.3, 0.9, 0.8), "size": 0.2,
		"gravity": Vector3(0, 0.5, 0), "spread": 80.0, "speed": 2.0},
	"lava_pop": {"amount": 6, "lifetime": 0.9, "color": Color(1.0, 0.5, 0.1), "size": 0.18,
		"gravity": Vector3(0, -8, 0), "spread": 40.0, "speed": 5.0},
}

var _emitters: Dictionary = {}
var enabled: bool = true


func _ready() -> void:
	name = "ParticleFx"
	_build()
	Settings.changed.connect(func(key: String, value: Variant) -> void:
		if key == "particles":
			enabled = bool(value)
			for kind in _emitters:
				(_emitters[kind] as GPUParticles3D).emitting = false
	)


func _build() -> void:
	for kind in KINDS:
		var spec: Dictionary = KINDS[kind]
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = 0.25
		process.direction = Vector3(0, 1, 0)
		process.spread = float(spec["spread"])
		process.gravity = spec["gravity"]
		process.initial_velocity_min = float(spec["speed"]) * 0.5
		process.initial_velocity_max = float(spec["speed"])
		process.scale_min = 0.6
		process.scale_max = 1.3
		process.damping_min = 0.4
		process.damping_max = 1.2

		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = spec["color"]
		material.vertex_color_use_as_albedo = true
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.disable_receive_shadows = true
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

		var quad := QuadMesh.new()
		var size: float = float(spec["size"])
		quad.size = Vector2(size, size)
		quad.material = material

		var particles := GPUParticles3D.new()
		particles.name = "Fx_%s" % kind
		particles.amount = int(spec["amount"])
		particles.lifetime = float(spec["lifetime"])
		particles.one_shot = true
		particles.explosiveness = 0.95
		particles.emitting = false
		particles.process_material = process
		particles.draw_pass_1 = quad
		particles.local_coords = false
		particles.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
		add_child(particles)
		_emitters[kind] = particles


## Fires a burst of particles at a world position.
func spawn(kind: String, position: Vector3, count: int = 0, tint: Color = Color.WHITE) -> void:
	if not enabled:
		return
	var particles: GPUParticles3D = _emitters.get(kind)
	if particles == null:
		return
	var mesh: QuadMesh = particles.draw_pass_1
	if tint != Color.WHITE and mesh != null:
		var material: StandardMaterial3D = mesh.material
		if material != null:
			material.albedo_color = Color(tint.r, tint.g, tint.b, material.albedo_color.a)
	if count > 0:
		particles.amount = clampi(count, 1, 120)
	particles.global_position = position
	particles.restart()
	particles.emitting = true
