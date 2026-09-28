extends CharacterBody3D

@export var speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var touch_sensitivity: float = 0.005
@export var camera_vertical_limit: float = 89.0
@export var camera_smoothness: float = 0.15

@export var fuerza_agarre: float = 15.0
@export var grupo_agarrable: String = "agarrable"

@onready var pivot: Node3D = $Pivot
@onready var camera: Camera3D = $Pivot/Camera3D
@onready var ray_cast_3d: RayCast3D = $Pivot/RayCast3D
@onready var grab_marker: Marker3D = $Pivot/Camera3D/Marker3D
@onready var grab_button: TouchScreenButton = $CanvasLayer/Control/Control/TouchScreenButton2
@onready var jump_button: TouchScreenButton = $CanvasLayer/Control/Control/salto

var current_speed: float
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var camera_x_rotation: float = 0.0
var target_y_rotation: float = 0.0
var current_y_rotation: float = 0.0
var look_delta: Vector2 = Vector2.ZERO
var touch_map: Dictionary = {}

var objeto_agarrado_node: RigidBody3D = null
var objeto_agarrado_rid: RID = RID()

var boton_salto_activo: bool = false


func _ready() -> void:
	add_to_group("jugador")
	camera.current = true
	current_speed = speed
	current_y_rotation = rotation.y
	target_y_rotation = rotation.y

	if grab_button:
		grab_button.visible = false

	if jump_button:
		jump_button.pressed.connect(func(): boton_salto_activo = true)
		jump_button.released.connect(func(): boton_salto_activo = false)


func _physics_process(delta: float) -> void:
	if look_delta != Vector2.ZERO:
		target_y_rotation -= look_delta.x
		camera_x_rotation -= look_delta.y

		var max_rad = deg_to_rad(camera_vertical_limit)
		camera_x_rotation = clamp(camera_x_rotation, -max_rad, max_rad)
		look_delta = Vector2.ZERO

	current_y_rotation = lerp(current_y_rotation, target_y_rotation, camera_smoothness)
	rotation.y = current_y_rotation
	pivot.rotation.x = lerp(pivot.rotation.x, camera_x_rotation, camera_smoothness)

	if (Input.is_action_just_pressed("ui_accept") or boton_salto_activo) and is_on_floor():
		velocity.y = jump_velocity
		boton_salto_activo = false

	if not is_on_floor():
		velocity.y -= gravity * delta

	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()

	if Input.is_action_just_pressed("ui_select"):
		if objeto_agarrado_node or objeto_agarrado_rid.is_valid():
			soltar_objeto()
		else:
			intentar_agarrar_objeto()

	procesar_agarre()


func _input(event: InputEvent) -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		if event.pressed:
			var pos_normalized = event.position / viewport_size
			touch_map[event.index] = {
				"position": event.position,
				"side": "right" if pos_normalized.x > 0.5 else "left"
			}
		else:
			if touch_map.has(event.index):
				touch_map.erase(event.index)

	if event is InputEventScreenDrag:
		if touch_map.has(event.index):
			var touch_data = touch_map[event.index]
			var touch_delta = event.position - touch_data.position
			touch_data.position = event.position

			var pos_normalized = event.position / viewport_size
			if pos_normalized.x > 0.5:
				look_delta += touch_delta * touch_sensitivity


func _es_rid_agarrable(rid: RID) -> bool:
	if not rid.is_valid(): return false
	for spawner in get_tree().get_nodes_in_group("spawners_agarrables"):
		if spawner.has_method("contiene_rid") and spawner.contiene_rid(rid):
			return true
	return false


func procesar_agarre() -> void:
	if objeto_agarrado_node:
		if grab_button: grab_button.visible = true
		var target_pos = grab_marker.global_position
		var direccion = target_pos - objeto_agarrado_node.global_position
		objeto_agarrado_node.linear_velocity = direccion * fuerza_agarre
		objeto_agarrado_node.angular_velocity *= 0.9

	elif objeto_agarrado_rid.is_valid():
		if grab_button: grab_button.visible = true
		var ps3d := PhysicsServer3D
		var target_pos = grab_marker.global_position
		var trans: Transform3D = ps3d.body_get_state(objeto_agarrado_rid, PhysicsServer3D.BODY_STATE_TRANSFORM)
		var direccion = target_pos - trans.origin

		ps3d.body_set_state(objeto_agarrado_rid, PhysicsServer3D.BODY_STATE_SLEEPING, false)
		ps3d.body_set_state(objeto_agarrado_rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, direccion * fuerza_agarre)

		var ang_vel: Vector3 = ps3d.body_get_state(objeto_agarrado_rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		ps3d.body_set_state(objeto_agarrado_rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, ang_vel * 0.9)

	else:
		if ray_cast_3d.is_colliding():
			var colision = ray_cast_3d.get_collider()
			var colision_rid = ray_cast_3d.get_collider_rid()

			var es_nodo_valido = colision is RigidBody3D and colision.is_in_group(grupo_agarrable)
			var es_rid_valido = _es_rid_agarrable(colision_rid)

			if grab_button: grab_button.visible = es_nodo_valido or es_rid_valido
		else:
			if grab_button: grab_button.visible = false


func intentar_agarrar_objeto() -> void:
	if not ray_cast_3d.is_colliding(): return

	var colision = ray_cast_3d.get_collider()
	var colision_rid = ray_cast_3d.get_collider_rid()

	if colision is RigidBody3D and colision.is_in_group(grupo_agarrable):
		objeto_agarrado_node = colision
		objeto_agarrado_node.gravity_scale = 0.0
		add_collision_exception_with(objeto_agarrado_node)
		return

	if _es_rid_agarrable(colision_rid):
		objeto_agarrado_rid = colision_rid
		PhysicsServer3D.body_set_param(objeto_agarrado_rid, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)


func soltar_objeto() -> void:
	if objeto_agarrado_node:
		remove_collision_exception_with(objeto_agarrado_node)
		objeto_agarrado_node.gravity_scale = 1.0
		objeto_agarrado_node = null

	if objeto_agarrado_rid.is_valid():
		PhysicsServer3D.body_set_param(objeto_agarrado_rid, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 1.0)
		objeto_agarrado_rid = RID()
