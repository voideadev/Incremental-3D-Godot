extends Marker3D  # Este script hace de "spawner": desde aquí se crean todos los bloques. La clave es que NO usamos RigidBody3D normales, sino el PhysicsServer directamente, así podemos tener miles sin que el juego muera.

@export var mesh_cubo: Mesh  # La forma visual del bloque. Puede ser un cubo o cualquier modelo tuyo.
@export var collision_shape: Shape3D  # La forma física. Ojo: no es lo mismo que el mesh, aquí es lo que choca.
@export var elasticidad: float = 0.5  # Cuánto rebota. 0 = se queda tieso, 1 = rebote casi infinito.
@export var friccion: float = 0.8  # Cuánto se desliza. Alto = se frena rápido, bajo = resbala como hielo.
@export var masa: float = 1.0  # El peso. Más masa = más cuesta moverlo y más se apila.
@export var offset_spawn: Vector3 = Vector3(0, 20, 0)  # Dónde aparecen respecto al marker. Por defecto 20 arriba para que caigan.

@export_group("Botón")
@export var boton: BaseButton
@export var accion_input: StringName = &"spawn_bloque"
@export var max_bloques: int = 3000  # El tope. Cuando llegas aquí, deja de crear (y para los timers).

@export_group("Auto-repetición al mantener")
@export var usar_auto_repeticion: bool = true  # Si lo dejas activado, al mantener pulsado sigue creando solo.
@export var delay_inicial_mantener: float = 0.4  # Espera antes de empezar a repetir. Así no spamea si fue un click rápido.
@export var cadencia_mantener: float = 0.001  # Muy rápido. Aquí está el truco para llenar la escena en segundos.

@export_group("Interfaz (UI)")
@export var label_cantidad: Label
@export var prefijo_label: String = "Bloques: "

var cuerpos: Array[RID] = []  # Aquí guardamos todos los cuerpos. Usamos RID porque son cuerpos del PhysicsServer, no nodos. Mucho más ligero.
var multimesh: MultiMesh
var mm_instance: MultiMeshInstance3D  # El MultiMesh dibuja todos los bloques de una sola vez. Por eso puedes tener miles sin que baje los FPS.
var rid_a_indice: Dictionary = {}  # Truco para saber qué cuerpo corresponde a qué instancia del MultiMesh.

var _timer_delay: Timer
var _timer_repeticion: Timer


func _ready() -> void:
	add_to_group("spawners_agarrables")
	_crear_multimesh()
	_configurar_timers()

	if boton:
		boton.button_down.connect(_on_boton_down)
		boton.button_up.connect(_on_boton_up)

	_actualizar_label()


func _unhandled_input(event: InputEvent) -> void:
	if accion_input == &"":
		return
	if event.is_action_pressed(accion_input):
		_on_input_action_down()
	elif event.is_action_released(accion_input):
		_on_input_action_up()


func _on_input_action_down() -> void:
	instanciar_bloque()
	if usar_auto_repeticion:
		_timer_delay.start()


func _on_input_action_up() -> void:
	if usar_auto_repeticion:
		_timer_delay.stop()
		_timer_repeticion.stop()


func _on_boton_down() -> void:
	instanciar_bloque()
	if usar_auto_repeticion:
		_timer_delay.start()


func _on_boton_up() -> void:
	if usar_auto_repeticion:
		_timer_delay.stop()
		_timer_repeticion.stop()


func _configurar_timers() -> void:
	# Dos timers: uno espera el delay inicial, el otro repite sin parar.
	_timer_delay = Timer.new()
	_timer_delay.wait_time = delay_inicial_mantener
	_timer_delay.one_shot = true
	_timer_delay.timeout.connect(func(): _timer_repeticion.start())
	add_child(_timer_delay)

	_timer_repeticion = Timer.new()
	_timer_repeticion.wait_time = cadencia_mantener
	_timer_repeticion.one_shot = false
	_timer_repeticion.timeout.connect(instanciar_bloque)
	add_child(_timer_repeticion)


func _crear_multimesh() -> void:
	# Preparamos el MultiMesh una sola vez con el máximo de instancias. Luego solo mostramos las que vamos usando (visible_instance_count).
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = false
	multimesh.use_custom_data = false
	multimesh.mesh = mesh_cubo
	multimesh.instance_count = max_bloques
	multimesh.visible_instance_count = 0

	mm_instance = MultiMeshInstance3D.new()
	mm_instance.multimesh = multimesh
	get_tree().current_scene.call_deferred("add_child", mm_instance)


func instanciar_bloque() -> int:
	if not mesh_cubo or not collision_shape:
		return -1

	if cuerpos.size() >= max_bloques:
		_timer_repeticion.stop()
		_timer_delay.stop()
		return -1

	var espacio := get_world_3d().space
	var ps3d := PhysicsServer3D

	var pos_inicial := global_position + offset_spawn
	var xform := Transform3D(Basis(), pos_inicial)

	# Aquí está la magia: creamos el cuerpo directo en el servidor físico. Nada de nodos, nada de escenas instanciadas. Puro RID.
	var body := ps3d.body_create()
	ps3d.body_set_space(body, espacio)
	ps3d.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
	ps3d.body_add_shape(body, collision_shape.get_rid())

	ps3d.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, xform)
	ps3d.body_set_param(body, PhysicsServer3D.BODY_PARAM_BOUNCE, elasticidad)
	ps3d.body_set_param(body, PhysicsServer3D.BODY_PARAM_FRICTION, friccion)
	ps3d.body_set_param(body, PhysicsServer3D.BODY_PARAM_MASS, masa)
	ps3d.body_set_state(body, PhysicsServer3D.BODY_STATE_SLEEPING, false)
	ps3d.body_set_state(body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, true)  # Lo de "can_sleep" es importante: si un bloque se queda quieto, el motor deja de calcularlo y ahorras un montón de recursos.

	var idx_local := multimesh.visible_instance_count
	cuerpos.append(body)
	rid_a_indice[body] = idx_local
	multimesh.set_instance_transform(idx_local, xform)
	multimesh.visible_instance_count += 1

	_actualizar_label()
	return idx_local


func _physics_process(_delta: float) -> void:
	# Cada frame copiamos la posición física al MultiMesh. Esto es lo que hace que se vean moverse aunque sean RIDs.
	var ps3d := PhysicsServer3D
	for i in range(cuerpos.size()):
		var body := cuerpos[i]
		if not body.is_valid():
			continue
		var trans := ps3d.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D
		multimesh.set_instance_transform(i, trans)


func contiene_rid(rid: RID) -> bool:
	return rid_a_indice.has(rid)


func _actualizar_label() -> void:
	if label_cantidad:
		label_cantidad.text = prefijo_label + str(cuerpos.size()) + " / " + str(max_bloques)


func _exit_tree() -> void:
	# Limpieza. Si no liberas los RIDs, se quedan ahí como fantasmas.
	for body in cuerpos:
		if body.is_valid():
			PhysicsServer3D.free_rid(body)
	cuerpos.clear()
	rid_a_indice.clear()
