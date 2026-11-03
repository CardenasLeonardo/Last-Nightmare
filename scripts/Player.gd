extends CharacterBody3D

## Movimiento tipo "over the shoulder" (Silent Hill 2 Remake / RE4 style):
## - El mouse orbita la cámara alrededor del personaje (yaw en CameraPivot, pitch en SpringArm3D).
## - WASD mueve al personaje en relación a hacia donde mira la cámara.
## - El origen (0,0,0) de este nodo representa los pies del personaje.
##
## Espacio:
## - Toque simple en el piso -> salto normal (con una ventana corta para detectar un segundo toque).
## - Doble toque rápido en el piso -> dash horizontal.
## - Toque simple en el aire -> segundo salto (doble salto), inmediato.
## - Mantener presionado tras agotar el doble salto mientras caes -> planeo (caída lenta).

@export var walk_speed: float = 2
@export var run_speed: float = 10
@export var crouch_speed: float = 1.2
## Se recalculan automáticamente en _ready() a partir de las Proporciones
## (ver _sync_body_to_proportions); estos valores solo aplican como fallback
## antes de que el esqueleto esté listo.
@export var stand_height: float = 1.8
@export var crouch_height: float = 1.0
@export var acceleration: float = 10
@export var rotation_speed: float = 8.0
@export var mouse_sensitivity: float = 0.0025
@export var pitch_min_deg: float = -35.0
@export var pitch_max_deg: float = 15.0
@export var zoom_speed: float = 0.5
@export var zoom_min: float = 1
@export var zoom_max: float = 6.0
@export var jump_velocity: float = 8
## Multiplica la gravedad base del proyecto (ProjectSettings). 1.0 = caída normal,
## <1.0 = caída más lenta/flotante, >1.0 = caída más rápida/pesada.
@export var gravity_scale: float = 1.8
## Límite de velocidad de caída (m/s). Si querés que nunca caiga más rápido que
## cierto valor (evita que se sienta "de cristal" en caídas largas), bajalo.
@export var max_fall_speed: float = 20
@export var max_jumps: int = 2
## Si está activo, el personaje no puede moverse mientras dura la animación de
## aterrizaje (Jump_Land) — evita que salga caminando/corriendo a mitad de la
## animación, como si nunca hubiera terminado de "asentarse" en el piso.
@export var landing_lock_enabled: bool = true
## Qué fracción de la duración de Jump_Land bloquea el movimiento (1.0 = toda
## la animación; 0.5 = se puede volver a mover a mitad de la animación).
@export_range(0.0, 1.0) var landing_lock_ratio: float = 1.0
## Si mantenés Shift o Ctrl al momento exacto de aterrizar, Jump_Land se salta
## por completo (ver _physics_process): encadenarla con Sprint/Crouch se veía
## como una doble flexión/aterrizaje cortado. landing_lock_ratio solo aplica
## a un aterrizaje "normal" (sin esas teclas en ese instante), y se fija una
## sola vez al tocar el piso — presionar Shift/Ctrl A MITAD de esa animación
## ya no desbloquea el movimiento antes de tiempo.
@export var dash_speed: float = 10.0
@export var dash_duration: float = 0.1
## Cuánto tiempo se mantiene la animación de Roll una vez termina el impulso físico
## del dash (el clip completo dura ~1.47s; con esto se ve un roll completo en vez
## de cortarse a los 0.2s del dash real).
@export var roll_anim_duration: float = 0.8
@export var double_tap_window: float = 0.3
@export var glide_fall_speed: float = 6

# ---------------------------------------------------------------------------
# PROPORCIONES ("look" Little Nightmares) — edítalos a mano y con F6 recargás.
# Cada uno escala un hueso del esqueleto. 1.0 = tamaño original del modelo.
# Todos los huesos de la cadena de torso/cuello/brazos/piernas comparten el
# mismo esquema local: eje Y = largo del hueso, ejes X/Z = grosor.
# Los nuevos (los que no venían del pedido original) arrancan en 1.0 (sin
# cambio) para no alterar el look ya ajustado; tocalos a gusto.
# ---------------------------------------------------------------------------
@export_group("Proporciones")

@export_subgroup("Cabeza y cuello")
@export var head_scale: float         = 4.5    # tamaño de la cabeza
@export var neck_length_scale: float  = 0.5  # largo del cuello (neck_01)
@export var neck_width_scale: float   = 0.5   # grosor del cuello (neck_01)

@export_subgroup("Torso")
@export var torso_scale: float        = 0.7   # cintura/abdomen (spine_01, raíz de todo lo de arriba: baja también la cabeza en pantalla, ver nota abajo)
@export var chest_scale: float        = 0.7   # pecho medio (spine_02)
@export var upper_chest_scale: float  = 1.2   # pecho alto (spine_03, de acá cuelgan cuello, hombros y brazos)
@export var pelvis_scale: float       = 0.6   # tamaño de cadera/glúteos (torso/piernas se compensan para no cambiar de tamaño con esto, ver _apply_proportions)

@export_subgroup("Brazos")
@export var shoulder_width_scale: float  = 1.3   # ancho de hombros (clavicle_*, no cambia el largo del brazo)
@export var arm_length_scale: float      = 0.8   # largo del brazo (upperarm_*, eje Y local)
@export var arm_width_scale: float       = 1   # grosor del brazo (upperarm_*, ejes X/Z locales)
@export var forearm_length_scale: float  = 1.1   # largo del antebrazo (lowerarm_*)
@export var forearm_width_scale: float   = 0.8   # grosor del antebrazo (lowerarm_*)
@export var hand_scale: float            = 1   # tamaño de manos (uniforme)

@export_subgroup("Piernas")
@export var leg_scale: float          = 0.7   # largo Y grosor del muslo (thigh_*, uniforme)
@export var shin_length_scale: float  = 0.9   # largo de la pantorrilla (calf_*)
@export var shin_width_scale: float   = 0.7   # grosor de la pantorrilla (calf_*)
@export var foot_scale: float         = 1.2   # tamaño de pies (uniforme)

@export_subgroup("Suéter")
## 0 = manga ajustada tal cual vino del modelo, 1 = manga más ancha (+6cm aprox., ver MAX_SLEEVE_WIDE en _setup_sweater).
@export_range(0.0, 1.0) var sweater_sleeve_width: float = 0.7
## 0 = largo original, 1 = manga más larga (+18cm aprox. hacia la mano, ver MAX_SLEEVE_LEN).
@export_range(0.0, 1.0) var sweater_sleeve_length: float = 1
## 0 = torso ajustado tal cual vino del modelo, 1 = cuerpo más ancho/suelto (+6cm aprox.).
@export_range(0.0, 1.0) var sweater_body_width: float = 1
## 0 = largo original, 1 = ruedo más largo hacia abajo (+20cm aprox., ver MAX_BODY_LEN).
@export_range(0.0, 1.0) var sweater_body_length: float = 0.5
## Entallado de cintura/torso: encoge X/Z hacia el eje central (0 = sin
## cambio, 1 = mitad del ancho). Solo afecta vértices pesados a huesos del
## torso (spine_01/02/03, pelvis, neck_01), así que mangas y hombros no se
## tocan. Se aplica antes de los sliders de arriba, tanto a la malla base
## como a cada blend shape, para que el ajuste se mantenga sin importar el
## valor de sweater_body_width/length. Ver _apply_sweater_waist_fit.
@export_range(0.0, 0.6) var sweater_waist_fit: float = 0.2
## Cuánto se compacta el ruedo (el borde de abajo del torso), simulando un
## elástico que junta la tela: 0 = sin extra (solo sweater_waist_fit parejo),
## 1 = ruedo muy apretado. Se suma a sweater_waist_fit solo cerca del borde
## inferior (ver sweater_hem_height), no en todo el torso.
@export_range(0.0, 0.8) var sweater_hem_elastic: float = 0.35
## Qué porción de la altura del torso queda afectada por el "elástico" del
## ruedo (0.22 = el 22% de abajo). Más arriba de esa franja, el entallado
## vuelve a ser solo sweater_waist_fit.
@export_range(0.0, 0.6) var sweater_hem_height: float = 0.22
## Adelgaza las mangas (upperarm/lowerarm), encogiéndolas hacia el eje del
## hueso correspondiente (no hacia el centro del cuerpo, para no acortarlas
## ni desplazarlas): 0 = grosor original, 1 = casi sin volumen. Ver
## _apply_sweater_sleeve_slim.
@export_range(0.0, 0.8) var sweater_sleeve_slim: float = 0.3
## Qué tan angosto queda el hombro: 0 = ancho de T-pose completo (el punto
## donde arranca el brazo queda lejos del cuello, efecto "hombrera"), 1 =
## hombro caído/angosto. Gira el propio clavicle (antes del upperarm), así
## se achica el punto de partida de la manga en vez de solo doblar el brazo.
## Ver _drape_sweater_sleeves.
@export_range(0.0, 1.0) var sweater_shoulder_slope: float = 0.0
## Redondea la parte de arriba del hombro (el "gorro" donde termina la manga
## sobre el clavicle): 0 = sin cambio (tope plano/anguloso), 1 = tope bien
## curvo tipo domo. Afecta a los vértices pesados a clavicle_l/r o
## upperarm_l/r que quedan por encima de la articulación del hombro (donde
## el clavicle se une al upperarm, en rest). Ver _apply_sweater_shoulder_round.
@export_range(0.0, 1.0) var sweater_shoulder_round: float = 0.4
## Ajuste de posición del suéter completo, en metros, relativo a donde queda
## por defecto (Y positivo = sube, Z positivo = hacia adelante). Se aplica
## como offset del MeshInstance3D, no mueve el cuerpo ni el esqueleto.
@export var sweater_offset: Vector3 = Vector3(0.0,0,0.02)
## Cuánto "cae" la manga desde el hombro (ver _drape_sweater_sleeves): 0 =
## brazo entero estirado en T-pose (como colgado de una percha), 1 = brazo
## entero apuntando derecho hacia abajo. El antebrazo siempre termina
## apuntando derecho hacia abajo (como si la gravedad lo tirara); este slider
## solo controla qué tan rápido se "cae" el brazo superior, así que valores
## bajos dejan más manga con pinta de T-pose cerca del hombro.
@export_range(0.0, 1.0) var sweater_sleeve_drape: float = 0.45

# ---------------------------------------------------------------------------
# CABELLO: el Mannequin_F no trae malla de pelo, así que se arma acá con
# geometría simple (dos esferas: "casco" arriba + "melena" atrás) pegada al
# hueso Head con un BoneAttachment3D. Al colgar del hueso Head, escala solo
# sola cuando cambiás head_scale arriba. Todo en unidades "base" (antes de
# head_scale), tocalos a ojo y F6 para ver el resultado.
# ---------------------------------------------------------------------------
@export_subgroup("Cabello")
@export var hair_enabled: bool = false   # esferas provisorias apagadas; se reemplaza por asset de pelo real
@export var hair_color: Color = Color(0.09, 0.07, 0.06)   # casi negro, estilo Six
@export var hair_radius: float = 0.08                    # tamaño del casco (cubre el cráneo)
@export var hair_top_offset: Vector3 = Vector3(0, 0.2, 0)     # dónde se centra el casco resp. al hueso Head
@export var hair_back_length: float = 1                # cuánto se alarga la melena hacia atrás/abajo
@export var hair_back_offset: Vector3 = Vector3(0, -0.03, -0.05) # posición de la melena trasera; si queda "para adelante", invertí el signo de Z

# ---------------------------------------------------------------------------
# CABELLO REAL (addons/tressfx): pelo simulado de verdad, reutiliza los
# assets .tfx/.tfxbone de la demo "ponytail" (rígida, sin esqueleto propio,
# por eso no importa que nuestro rig sea distinto al de "Ruby"). La demo está
# armada a escala humana real con origen en el pecho (cabeza en Y=0.9); acá
# se re-ancla todo para que el origen quede en el cráneo y se re-escala con
# hair_tfx_scale. Es una primera aproximación a ojo: ajustá hair_tfx_scale
# y hair_tfx_offset una vez que lo veas correr (F6).
# Requiere haber reiniciado el editor una vez tras instalar el addon para
# que sus compute shaders se importen (ver addons/tressfx/README.md).
# ---------------------------------------------------------------------------
@export_subgroup("Cabello real (TressFX)")
@export var hair_tfx_enabled: bool = false   # reemplazado por el pelo toon (ver abajo); se deja el código por si se quiere retomar
@export var hair_tfx_tail_enabled: bool = false   # cola de caballo apagada: pelo corto (solo cuero cabelludo)
@export var hair_tfx_scale: float = 1.0     # multiplicador extra sobre el auto-escalado por hair_radius
@export var hair_tfx_offset: Vector3 = Vector3.ZERO   # ajuste fino de posición sobre hair_top_offset

# ---------------------------------------------------------------------------
# CABELLO TOON (VRoid Studio + shader SimpleToonHair): malla real exportada
# desde VRoid Studio (res://Godot/Hair/hinata_hair.tscn, generada a partir de
# res://Godot/Hair/avatar_source.glb con las texturas propias del corte que
# armaste). Cuelga del hueso Head, y tiene una física liviana tipo "lámina"
# (no por hebra): un resorte inercial en GDScript reacciona a la velocidad
# del personaje, y el shader amplifica ese desplazamiento hacia las puntas
# del mechón (ver _sway_offset/_root_y/_tip_range en el shader). El offset de
# reanclaje (VRM_HEAD_OFFSET) viene de medir dónde está el hueso "cabeza" del
# VRM exportado (J_Bip_C_Head) en su propio espacio: si volvés a exportar un
# corte distinto desde VRoid y el pelo queda desplazado, es el primer valor a
# revisar.
# ---------------------------------------------------------------------------
@export_subgroup("Cabello toon (VRoid)")
@export var hair_toon_enabled: bool = true
@export var hair_toon_scale: float = 1
@export var hair_toon_offset: Vector3 = Vector3.ZERO
## Física liviana tipo "resorte" en las láminas de pelo (no es por hebra: mueve
## toda la malla del mechón, con más fuerza en las puntas gracias al shader).
## Reacciona a la velocidad del personaje: al moverte/girar, el pelo queda
## un poco atrás y "recupera" con resorte+amortiguación.
@export var hair_sway_enabled: bool = true
@export var hair_sway_response: float = 20.0   # rigidez del resorte: más alto = vuelve más rápido a su lugar
@export var hair_sway_damping: float = 5.0     # amortiguación: más alto = menos rebote
@export var hair_sway_strength: float = 0.03   # cuánto desplazamiento genera la velocidad del personaje
@export var hair_sway_max: float = 0.05        # tope de desplazamiento en metros

@export_subgroup("Ojos")
@export var eye_scale: float = 1.5         # tamaño de los ojos (escala uniforme del quad)
@export var eye_separation: float = 0.1 # distancia horizontal entre el ojo izq. y der. (centro a centro)
@export var eye_height: float = 1.406321    # altura (Y local, respecto a la raíz del pelo) de los ojos
@export var eye_forward: float = 0.1 # profundidad (Z local); si quedan tapados por el fleco, subí este valor o el no_depth_test del material ya los hace "asomar"

@export_subgroup("Rostro sombra")
@export var face_shadow_enabled: bool = true
@export var face_shadow_offset: float = -0.05   # ajuste relativo a la altura del hueso Head (negativo = el corte baja hacia el cuello)
@export var face_shadow_softness: float = 0.01  # ancho del degradado del borde del corte
@export var face_shadow_color: Color = Color(0.02, 0.02, 0.03)
@export var face_shadow_fresnel: float = 0.25   # brillo tenue en el borde, para que la sombra "se desprenda" en vez de cortar en línea recta

@export_subgroup("Color del cuerpo")
@export var body_color: Color = Color(0.55, 0.55, 0.6)   # piel/cuerpo (superficie M_Main), gris
@export var joints_color: Color = Color(0.42, 0.3, 0.55)  # uniones/costuras (superficie M_Joints), morado

const FACE_SHADOW_SHADER := "res://Godot/Shaders/FaceShadow.gdshader"
const HINATA_HAIR_SCENE := "res://Godot/Hair/hinata_hair.tscn"
const VRM_HEAD_OFFSET := Vector3(0.0, -1.31, 0.019239)

const TRESSFX_DIR := "res://addons/tressfx/demo/ponytail/"
const TRESSFX_HEAD_Y_IN_DEMO := 0.9  # altura de la cabeza en el rig original de la demo (origen = pecho)

# Nota: torso_scale y head_scale se combinan (torso_scale también achica la
# cabeza al reducir todo lo que cuelga de spine_01); si la cabeza queda chica,
# subí head_scale para compensar. En cascada aplica igual a chest_scale /
# upper_chest_scale / shoulder_width_scale / arm_*_scale, montados sobre
# torso_scale.

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var mesh: Node3D = $CharacterMesh
@onready var skeleton: Skeleton3D = $CharacterMesh/Armature/Skeleton3D
@onready var anim_player: AnimationPlayer = $CharacterMesh/AnimationPlayer
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var measured_head_y: float = 0.0   # altura (Y local) del hueso Head ya escalado, medida en _sync_body_to_proportions

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var jumps_used: int = 0
var jump_requested: bool = false
var jump_pending: bool = false
var jump_pending_timer: float = 0.0
var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_dir: Vector3 = Vector3.ZERO
var roll_anim_timer: float = 0.0
var is_crouching: bool = false
var prev_on_floor: bool = true
var landing_timer: float = 0.0
var landing_duration: float = 0.1
var jump_start_duration: float = 0.1
# Ratio de desbloqueo de un aterrizaje "normal" (sin Shift/Ctrl al tocar el
# piso), fijado una sola vez en ese instante — ver _physics_process.
var landing_recovery_ratio: float = 1.0

const ANIM_IDLE: StringName = &"Idle"
const ANIM_WALK: StringName = &"Walk"
const ANIM_RUN: StringName = &"Sprint"
const ANIM_JUMP_START: StringName = &"Jump_Start"
const ANIM_JUMP_LOOP: StringName = &"Jump"
const ANIM_JUMP_LAND: StringName = &"Jump_Land"
const ANIM_CROUCH_IDLE: StringName = &"Crouch_Idle"
const ANIM_CROUCH_FWD: StringName = &"Crouch_Fwd"
const ANIM_ROLL: StringName = &"Roll"
const ANIM_BLEND_TIME: float = 0.25

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Duplicar el shape para que cambios de altura (agacharse) no afecten
	# a otras instancias que compartan el mismo SubResource.
	collision_shape.shape = collision_shape.shape.duplicate()
	_load_shared_animations()
	if anim_player.has_animation(ANIM_JUMP_LAND):
		landing_duration = anim_player.get_animation(ANIM_JUMP_LAND).length
	if anim_player.has_animation(ANIM_JUMP_START):
		jump_start_duration = anim_player.get_animation(ANIM_JUMP_START).length
	# Forzar una pose de referencia conocida (frame 0 de Idle) ANTES de medir el
	# esqueleto: sin esto, la medición dependía de lo que el AnimationPlayer
	# tuviera activo en ese instante (autoplay del import, pose en T, etc.),
	# dando una altura de pie distinta e impredecible cada vez.
	if anim_player.has_animation(ANIM_IDLE):
		anim_player.play(ANIM_IDLE)
		anim_player.seek(0.0, true)
	_apply_proportions()
	_setup_hair()
	_setup_tressfx_hair()
	_setup_toon_hair()
	_setup_face_shadow()
	_setup_sweater()

## El mesh actual (Mannequin_F, del pack UAL2) no trae animaciones propias:
## viene pensado para usarse con las librerías de UAL1/UAL2, que comparten
## exactamente el mismo esqueleto. Acá se carga la librería de animaciones
## desde UAL1_Standard.glb (sin instanciarlo en el árbol) y se la pegamos al
## AnimationPlayer vacío que está bajo CharacterMesh.
const SHARED_ANIM_SOURCE := "res://Godot/UAL1_Standard.glb"

func _load_shared_animations() -> void:
	if anim_player.get_animation_library_list().size() > 0:
		return # ya tiene animaciones propias (ej. si volvés al mesh original)
	var source_scene := load(SHARED_ANIM_SOURCE) as PackedScene
	if source_scene == null:
		push_warning("No se pudo cargar %s para las animaciones." % SHARED_ANIM_SOURCE)
		return
	var source_root := source_scene.instantiate()
	var source_player := source_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source_player:
		var lib := source_player.get_animation_library("")
		anim_player.add_animation_library("", lib)
	source_root.queue_free()

## Escala huesos del rig (esqueleto tipo UE Mannequin de UAL1) para dar look
## "niño frágil" de Little Nightmares. En este rig el eje Y local de cada
## hueso apunta hacia su hijo (verificado con las translations del glb), así
## que largo (Y) y grosor (X/Z) se pueden ajustar por separado sin deformar
## raro. Escalar un hueso "raíz" de una cadena (spine_01, upperarm_*,
## thigh_*, etc.) arrastra proporcionalmente todo lo que cuelga de él. Estas
## animaciones no tienen keys de escala, así que el override puesto acá no se
## pisa al reproducirlas.
func _apply_proportions() -> void:
	# "pelvis" es el hueso PADRE de spine_01 y de ambos thigh_*: en Godot, la
	# escala de un hueso se compone multiplicativamente hacia sus hijos (global
	# = local * padre). Si solo tocás pelvis_scale, thigh/spine heredan esa
	# escala también y todo el cuerpo cambia de tamaño con la cadera.
	# Para que pelvis_scale afecte SOLO la malla propia de la cadera (y el
	# punto donde se "insertan" torso/piernas, dando el efecto de cadera
	# angosta/ancha) sin encoger torso ni piernas, se compensa dividiendo la
	# escala local de spine_01/thigh_* por pelvis_scale: así el producto
	# compuesto (local * pelvis_scale) vuelve a dar exactamente torso_scale /
	# leg_scale, el tamaño absoluto que pediste para esas partes.
	var pelvis_compensation: float = 1.0 / max(pelvis_scale, 0.05)

	# Torso: spine_01 -> spine_02 -> spine_03
	_scale_bone(&"spine_01", Vector3.ONE * torso_scale * pelvis_compensation)
	_scale_bone(&"spine_02", Vector3.ONE * chest_scale)
	_scale_bone(&"spine_03", Vector3.ONE * upper_chest_scale)
	_scale_bone(&"pelvis", Vector3.ONE * pelvis_scale)

	# Cuello y cabeza: neck_01 -> Head
	_scale_bone(&"neck_01", Vector3(neck_width_scale, neck_length_scale, neck_width_scale))
	_scale_bone(&"Head", Vector3.ONE * head_scale)

	# Brazos y piernas: clavicle_* -> upperarm_* -> lowerarm_* -> hand_*
	#                   thigh_* -> calf_* -> foot_*
	for side in ["_l", "_r"]:
		_scale_bone("clavicle" + side, Vector3(shoulder_width_scale, 1.0, shoulder_width_scale))
		_scale_bone("upperarm" + side, Vector3(arm_width_scale, arm_length_scale, arm_width_scale))
		_scale_bone("lowerarm" + side, Vector3(forearm_width_scale, forearm_length_scale, forearm_width_scale))
		_scale_bone("hand" + side, Vector3.ONE * hand_scale)

		_scale_bone("thigh" + side, Vector3.ONE * leg_scale * pelvis_compensation)
		_scale_bone("calf" + side, Vector3(shin_width_scale, shin_length_scale, shin_width_scale))
		_scale_bone("foot" + side, Vector3.ONE * foot_scale)

	_sync_body_to_proportions()

func _scale_bone(bone_name: StringName, bone_scale: Vector3) -> void:
	var idx := skeleton.find_bone(bone_name)
	if idx != -1:
		skeleton.set_bone_pose_scale(idx, bone_scale)

## Suéter extraído de un avatar VRM (sueter.vrm / VRoid Studio) con sus pesos
## de piel re-mapeados a los nombres de hueso del rig UE Mannequin (ver
## Godot/Wardrobe/Sueter.glb). El bind (Sueter.glb) se calculó a partir del
## esqueleto SIN las escalas de "Proporciones" (ver _apply_proportions): esas
## escalas no son uniformes (ancho != largo por hueso) y encogen la cadena
## bastante, y al combinarse con las rotaciones fuertes de las animaciones
## producen "shear" — la prenda se deforma/encoge de forma fea o directamente
## desaparece. Por eso la prenda NO cuelga del Skeleton3D real, sino de un
## Skeleton3D "espejo" (sweater_skeleton) que cada frame copia posición y
## rotación de cada hueso (la animación) pero nunca la escala de
## Proporciones — así el suéter sigue el movimiento del cuerpo pero no la
## distorsión anisotrópica. Ver _sync_sweater_skeleton().
const SWEATER_SOURCE := "res://Godot/Wardrobe/Sueter.glb"

var sweater_skeleton: Skeleton3D

func _make_sweater_skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "SueterSkeleton"
	for i in skeleton.get_bone_count():
		sk.add_bone(skeleton.get_bone_name(i))
		sk.set_bone_parent(i, skeleton.get_bone_parent(i))
		sk.set_bone_rest(i, skeleton.get_bone_rest(i))
	skeleton.get_parent().add_child(sk)
	return sk

## Copia posición+rotación (NO escala) de cada hueso hacia el esqueleto
## "espejo" del suéter. Se llama todos los frames (ver _process) para que el
## suéter siga la animación del cuerpo (caminar, correr, saltar, etc.); los
## huesos de manga/hombro (clavicle/upperarm/lowerarm) quedan pisados un
## instante después por _drape_sweater_sleeves(), que en vez de la pose
## animada cruda aplica el estilizado (hombro angosto + manga que cae) sobre
## esos mismos huesos, para no volver al efecto "colgado de una percha".
func _sync_sweater_skeleton() -> void:
	if sweater_skeleton == null:
		return
	for i in skeleton.get_bone_count():
		sweater_skeleton.set_bone_pose_position(i, skeleton.get_bone_pose_position(i))
		sweater_skeleton.set_bone_pose_rotation(i, skeleton.get_bone_pose_rotation(i))

## Sincroniza el suéter con la animación del cuerpo todos los frames.
func _process(_delta: float) -> void:
	if sweater_skeleton == null:
		return
	_sync_sweater_skeleton()
	_drape_sweater_sleeves()

func _setup_sweater() -> void:
	var source_scene := load(SWEATER_SOURCE) as PackedScene
	if source_scene == null:
		push_warning("No se pudo cargar %s." % SWEATER_SOURCE)
		return
	var source_root := source_scene.instantiate()
	var sweater_mesh := source_root.find_child("Sueter", true, false) as MeshInstance3D
	if sweater_mesh == null:
		push_warning("Sueter.glb no tiene un MeshInstance3D llamado 'Sueter'.")
		source_root.queue_free()
		return
	sweater_mesh.get_parent().remove_child(sweater_mesh)
	sweater_mesh.owner = null
	sweater_skeleton = _make_sweater_skeleton()
	sweater_skeleton.add_child(sweater_mesh)
	sweater_mesh.skeleton = NodePath("..")
	sweater_mesh.position = sweater_offset
	source_root.queue_free()
	_apply_sweater_waist_fit(sweater_mesh) # entalla torso + ruedo ANTES de los blend shapes, para que persista con cualquier slider
	_apply_sweater_sleeve_slim(sweater_mesh) # adelgaza mangas, mismo momento (antes de los blend shapes)
	_apply_sweater_shoulder_round(sweater_mesh) # redondea el tope del hombro, mismo momento (antes de los blend shapes)
	_apply_sweater_fit(sweater_mesh)
	_sync_sweater_skeleton() # primer frame ya sincronizado; _process lo repite en cada frame siguiente
	_drape_sweater_sleeves() # dobla los brazos para que la manga "caiga" en vez de quedar recta

## Nombres de hueso (bind names) del Skin embebido, en el mismo orden que
## ARRAY_BONES referencia por índice.
func _sweater_bind_names(skin: Skin) -> PackedStringArray:
	var bind_names: PackedStringArray = PackedStringArray()
	for i in skin.get_bind_count():
		bind_names.append(skin.get_bind_name(i))
	return bind_names

## Arma un ArrayMesh nuevo a partir de arrays (malla base) + blend_shapes ya
## modificados, preservando nombres/modo de blend shape y material.
func _sweater_rebuild_mesh(mesh: ArrayMesh, base_arrays: Array, bs_arrays: Array) -> ArrayMesh:
	var new_mesh := ArrayMesh.new()
	new_mesh.blend_shape_mode = mesh.blend_shape_mode
	for i in mesh.get_blend_shape_count():
		new_mesh.add_blend_shape(mesh.get_blend_shape_name(i))
	new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, base_arrays, bs_arrays)
	new_mesh.surface_set_material(0, mesh.surface_get_material(0))
	return new_mesh

## Encoge (X/Z hacia el eje central) solo los vértices del torso, identificados
## por su hueso dominante de skin (spine_01/02/03, pelvis, neck_01) usando los
## bind names del Skin embebido — así mangas/hombros (clavicle/upperarm/...)
## no se tocan. Cerca del borde inferior del torso (el ruedo, ver
## sweater_hem_height) suma sweater_hem_elastic al encogimiento, simulando un
## elástico que junta la tela. Reconstruye el ArrayMesh completo (malla base +
## los 5 blend shapes horneados) con las posiciones ya encogidas, para que el
## entallado se mantenga sin importar qué valor tengan sweater_body_width/length.
func _apply_sweater_waist_fit(sweater_mesh: MeshInstance3D) -> void:
	if sweater_waist_fit <= 0.0 and sweater_hem_elastic <= 0.0:
		return
	var mesh: ArrayMesh = sweater_mesh.mesh
	var skin: Skin = sweater_mesh.skin
	if mesh == null or skin == null:
		return

	var bind_names := _sweater_bind_names(skin)
	var torso_bones := {"spine_01": true, "spine_02": true, "spine_03": true, "pelvis": true, "neck_01": true}

	var base_arrays: Array = mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = base_arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = base_arrays[Mesh.ARRAY_WEIGHTS]
	var base_positions: PackedVector3Array = base_arrays[Mesh.ARRAY_VERTEX]
	var vertex_count: int = base_positions.size()

	# torso_w[i]: cuánto pesa el torso en ese vértice (suma de pesos hacia
	# huesos del torso), 0..1. Da un borde suave donde el skin ya mezcla
	# torso/hombro en vez de un corte duro.
	var torso_w := PackedFloat32Array()
	torso_w.resize(vertex_count)
	for vi in vertex_count:
		var w := 0.0
		for k in 4:
			var bi: int = bones[vi * 4 + k]
			if bi >= 0 and bi < bind_names.size() and torso_bones.has(bind_names[bi]):
				w += weights[vi * 4 + k]
		torso_w[vi] = w

	# Rango Y del torso (solo vértices bien clasificados como torso), para
	# ubicar el ruedo (borde inferior) y calcular el degradado del elástico.
	var hem_min_y := INF
	var hem_max_y := -INF
	for vi in vertex_count:
		if torso_w[vi] > 0.5:
			hem_min_y = min(hem_min_y, base_positions[vi].y)
			hem_max_y = max(hem_max_y, base_positions[vi].y)
	var hem_range: float = max(hem_max_y - hem_min_y, 0.0001)

	var shrink_factor := PackedFloat32Array()
	shrink_factor.resize(vertex_count)
	for vi in vertex_count:
		var t: float = clamp((base_positions[vi].y - hem_min_y) / hem_range, 0.0, 1.0)
		var hem_t: float = 1.0 - smoothstep(0.0, sweater_hem_height, t) # 1 en el borde inferior, 0 más arriba de la franja
		shrink_factor[vi] = clamp((sweater_waist_fit + sweater_hem_elastic * hem_t) * torso_w[vi], 0.0, 0.9)

	var bs_arrays: Array = mesh.surface_get_blend_shape_arrays(0)
	var position_sets: Array = [base_positions]
	for shape_arrays in bs_arrays:
		position_sets.append(shape_arrays[Mesh.ARRAY_VERTEX])

	for positions in position_sets:
		var pv: PackedVector3Array = positions
		for vi in vertex_count:
			var factor: float = 1.0 - shrink_factor[vi]
			var p := pv[vi]
			pv[vi] = Vector3(p.x * factor, p.y, p.z * factor)

	base_arrays[Mesh.ARRAY_VERTEX] = position_sets[0]
	for i in bs_arrays.size():
		bs_arrays[i][Mesh.ARRAY_VERTEX] = position_sets[i + 1]

	sweater_mesh.mesh = _sweater_rebuild_mesh(mesh, base_arrays, bs_arrays)

## Adelgaza las mangas encogiendo cada vértice hacia el eje del segmento de
## hueso que más pesa sobre él (upperarm_l/r o lowerarm_l/r: el segmento va
## del origen de ese hueso al origen de su hijo, en rest), en vez de hacia el
## centro del cuerpo — así la manga se afina sin acortarse ni desplazarse
## hacia el torso. Vértices con influencia mixta (ej. cerca del codo, entre
## upperarm y lowerarm) se resuelven ponderando por el peso de cada hueso.
## Igual que _apply_sweater_waist_fit, reconstruye malla base + blend shapes.
func _apply_sweater_sleeve_slim(sweater_mesh: MeshInstance3D) -> void:
	if sweater_sleeve_slim <= 0.0:
		return
	var mesh: ArrayMesh = sweater_mesh.mesh
	var skin: Skin = sweater_mesh.skin
	if mesh == null or skin == null:
		return

	var bind_names := _sweater_bind_names(skin)
	var sleeve_child := {
		"clavicle_l": "upperarm_l", "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l",
		"clavicle_r": "upperarm_r", "upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r",
	}
	# Extremos (en rest, espacio local del suéter) de cada segmento de manga.
	var segment_a: Dictionary = {}
	var segment_b: Dictionary = {}
	for bone_name in sleeve_child:
		var idx := skeleton.find_bone(bone_name)
		var child_idx := skeleton.find_bone(sleeve_child[bone_name])
		if idx == -1 or child_idx == -1:
			continue
		segment_a[bone_name] = _bone_global_rest(skeleton, idx).origin
		segment_b[bone_name] = _bone_global_rest(skeleton, child_idx).origin

	var base_arrays: Array = mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = base_arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = base_arrays[Mesh.ARRAY_WEIGHTS]
	var vertex_count: int = (base_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()

	var bs_arrays: Array = mesh.surface_get_blend_shape_arrays(0)
	var position_sets: Array = [base_arrays[Mesh.ARRAY_VERTEX]]
	for shape_arrays in bs_arrays:
		position_sets.append(shape_arrays[Mesh.ARRAY_VERTEX])

	for positions in position_sets:
		var pv: PackedVector3Array = positions
		for vi in vertex_count:
			var p := pv[vi]
			var acc := Vector3.ZERO
			var acc_w := 0.0
			for k in 4:
				var bi: int = bones[vi * 4 + k]
				var w: float = weights[vi * 4 + k]
				if w <= 0.0 or bi < 0 or bi >= bind_names.size():
					continue
				var bname: String = bind_names[bi]
				if not segment_a.has(bname):
					continue
				var a: Vector3 = segment_a[bname]
				var b: Vector3 = segment_b[bname]
				var ab := b - a
				var ab_len2 := ab.length_squared()
				var t: float = clamp((p - a).dot(ab) / ab_len2, 0.0, 1.0) if ab_len2 > 0.0001 else 0.0
				var closest: Vector3 = a + ab * t
				var target: Vector3 = closest + (p - closest) * (1.0 - sweater_sleeve_slim)
				acc += target * w
				acc_w += w
			if acc_w > 0.0:
				pv[vi] = p * (1.0 - acc_w) + acc

	base_arrays[Mesh.ARRAY_VERTEX] = position_sets[0]
	for i in bs_arrays.size():
		bs_arrays[i][Mesh.ARRAY_VERTEX] = position_sets[i + 1]

	sweater_mesh.mesh = _sweater_rebuild_mesh(mesh, base_arrays, bs_arrays)

## Redondea el tope del hombro: los vértices pesados a clavicle_l/r o
## upperarm_l/r que quedan por encima de la articulación del hombro (donde
## el clavicle se une al upperarm, en rest) se acercan al eje vertical que
## pasa por esa articulación a medida que suben (y bajan un poco), así el
## "gorro" del hombro pasa de verse plano/anguloso a una curva tipo domo.
## El degradado (round_t) se normaliza por lado usando la altura máxima real
## de esos vértices, así el efecto siempre llega a full en el punto más alto
## sin importar el tamaño del suéter. Igual que las otras funciones de ajuste
## de malla, se aplica sobre malla base + blend shapes, en espacio de rest.
func _apply_sweater_shoulder_round(sweater_mesh: MeshInstance3D) -> void:
	if sweater_shoulder_round <= 0.0:
		return
	var mesh: ArrayMesh = sweater_mesh.mesh
	var skin: Skin = sweater_mesh.skin
	if mesh == null or skin == null:
		return

	var bind_names := _sweater_bind_names(skin)
	var shoulder_bones := {"clavicle_l": true, "upperarm_l": true, "clavicle_r": true, "upperarm_r": true}
	var joints := {}
	for side in ["_l", "_r"]:
		var up_idx := skeleton.find_bone("upperarm" + side)
		if up_idx == -1:
			continue
		joints[side] = _bone_global_rest(skeleton, up_idx).origin

	var base_arrays: Array = mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = base_arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = base_arrays[Mesh.ARRAY_WEIGHTS]
	var base_positions: PackedVector3Array = base_arrays[Mesh.ARRAY_VERTEX]
	var vertex_count: int = base_positions.size()

	# shoulder_w[i]: peso hacia clavicle/upperarm; side_of[i]: de qué lado
	# ("_l"/"_r") según el bind con más peso entre esos huesos.
	var shoulder_w := PackedFloat32Array()
	shoulder_w.resize(vertex_count)
	var side_of: Array = []
	side_of.resize(vertex_count)
	for vi in vertex_count:
		var w := 0.0
		var best_side := ""
		var best_w := 0.0
		for k in 4:
			var bi: int = bones[vi * 4 + k]
			if bi < 0 or bi >= bind_names.size():
				continue
			var bname: String = bind_names[bi]
			if not shoulder_bones.has(bname):
				continue
			var bw: float = weights[vi * 4 + k]
			w += bw
			if bw > best_w:
				best_w = bw
				best_side = "_l" if bname.ends_with("_l") else "_r"
		shoulder_w[vi] = w
		side_of[vi] = best_side

	# Altura máxima sobre la articulación entre los vértices de hombro, por
	# lado, para normalizar el degradado (1.0 justo en el punto más alto).
	var max_h := {"_l": 0.0001, "_r": 0.0001}
	for vi in vertex_count:
		var side: String = side_of[vi]
		if shoulder_w[vi] > 0.3 and joints.has(side):
			var h: float = base_positions[vi].y - (joints[side] as Vector3).y
			if h > max_h[side]:
				max_h[side] = h

	var bs_arrays: Array = mesh.surface_get_blend_shape_arrays(0)
	var position_sets: Array = [base_positions]
	for shape_arrays in bs_arrays:
		position_sets.append(shape_arrays[Mesh.ARRAY_VERTEX])

	for positions in position_sets:
		var pv: PackedVector3Array = positions
		for vi in vertex_count:
			var side: String = side_of[vi]
			if shoulder_w[vi] <= 0.0 or not joints.has(side):
				continue
			var joint: Vector3 = joints[side]
			var p := pv[vi]
			var h: float = p.y - joint.y
			if h <= 0.0:
				continue
			var round_t: float = clamp(h / max_h[side], 0.0, 1.0) * sweater_shoulder_round * shoulder_w[vi]
			var radial := Vector2(p.x - joint.x, p.z - joint.z)
			var radial_len := radial.length()
			var scale: float = (1.0 - round_t) if radial_len > 0.0001 else 1.0
			pv[vi] = Vector3(
				joint.x + (p.x - joint.x) * scale,
				p.y - h * round_t * 0.5,
				joint.z + (p.z - joint.z) * scale
			)

	base_arrays[Mesh.ARRAY_VERTEX] = position_sets[0]
	for i in bs_arrays.size():
		bs_arrays[i][Mesh.ARRAY_VERTEX] = position_sets[i + 1]

	sweater_mesh.mesh = _sweater_rebuild_mesh(mesh, base_arrays, bs_arrays)

## Transform global de un hueso en su pose de rest, calculado a mano
## recorriendo la cadena de padres (no depende de que exista
## get_bone_global_rest en esta versión de Godot).
func _bone_global_rest(skel: Skeleton3D, idx: int) -> Transform3D:
	var t := skel.get_bone_rest(idx)
	var parent_idx := skel.get_bone_parent(idx)
	while parent_idx != -1:
		t = skel.get_bone_rest(parent_idx) * t
		parent_idx = skel.get_bone_parent(parent_idx)
	return t

## El bind del suéter viene con los brazos estirados en línea recta (T-pose).
## Se llama todos los frames (ver _process). El angostado del hombro
## (clavicle, sweater_shoulder_slope) se mide SIEMPRE contra el rest (T-pose),
## no la animación: el clavicle casi no se anima (el brazo se mueve sobre
## todo rotando el upperarm), así que medirlo desde la pose real diluía el
## efecto según qué animación estuviera activa y volvía a verse "hombrera".
## El upperarm/lowerarm sí usan la pose animada real (ya copiada por
## _sync_sweater_skeleton) y se mezclan parcialmente hacia "derecho hacia
## abajo" para simular el peso de la tela: sweater_sleeve_drape controla
## cuánto (0 = sigue el brazo tal cual la animación, 1 = ya apunta derecho
## hacia abajo pase lo que pase el brazo) y el lowerarm siempre termina
## compensando hacia abajo. Así la manga se mueve con el brazo real sin
## perder el angostado de hombro ni la caída/estructura trabajada. La mano no
## se toca: hereda su rotación relativa (de _sync_sweater_skeleton) tal cual,
## así que conserva la muñeca de la animación en vez de quedar rígida.
func _drape_sweater_sleeves() -> void:
	if sweater_skeleton == null:
		return
	for side in ["_l", "_r"]:
		var up_idx := skeleton.find_bone("upperarm" + side)
		var low_idx := skeleton.find_bone("lowerarm" + side)
		if up_idx == -1 or low_idx == -1:
			continue
		var clavicle_idx := skeleton.get_bone_parent(up_idx)
		if clavicle_idx == -1:
			continue
		var clavicle_parent_idx := skeleton.get_bone_parent(clavicle_idx)
		if clavicle_parent_idx == -1:
			continue

		var down_dir := Vector3.DOWN

		# Clavicle: SIEMPRE contra el rest, para que el angostado del hombro
		# (sweater_shoulder_slope) dé el mismo resultado sin importar la
		# animación activa (en T-pose el clavicle apunta bien horizontal hacia
		# afuera, lo que deja el hombro tan ancho como el brazo estirado ->
		# "hombrera").
		var clavicle_rest := _bone_global_rest(skeleton, clavicle_idx)
		var clavicle_parent_rest := _bone_global_rest(skeleton, clavicle_parent_idx)
		var up_rest := _bone_global_rest(skeleton, up_idx)

		var clav_dir: Vector3 = (up_rest.origin - clavicle_rest.origin).normalized()
		var clav_target_dir: Vector3 = clav_dir.slerp(down_dir, sweater_shoulder_slope)
		var clav_delta := Quaternion(clav_dir, clav_target_dir)
		var clav_new_global_basis: Basis = Basis(clav_delta) * clavicle_rest.basis
		var clav_local_pose: Basis = clavicle_parent_rest.basis.inverse() * clav_new_global_basis
		sweater_skeleton.set_bone_pose_rotation(clavicle_idx, clav_local_pose.get_rotation_quaternion())

		# Upperarm/lowerarm: pose global ACTUAL (animada), no el rest fijo,
		# así la manga sigue el movimiento real del brazo.
		var up_pose := skeleton.get_bone_global_pose(up_idx)
		var low_pose := skeleton.get_bone_global_pose(low_idx)
		var arm_dir: Vector3 = (low_pose.origin - up_pose.origin).normalized() # dirección real del brazo en el frame actual

		# Upperarm: gira parcialmente desde su dirección real hacia "abajo",
		# medido desde el nuevo global del clavicle (ya angostado, fijo).
		var up_target_dir: Vector3 = arm_dir.slerp(down_dir, sweater_sleeve_drape)
		var up_delta := Quaternion(arm_dir, up_target_dir)
		var up_new_global_basis: Basis = Basis(up_delta) * up_pose.basis
		var up_local_pose: Basis = clav_new_global_basis.inverse() * up_new_global_basis
		sweater_skeleton.set_bone_pose_rotation(up_idx, up_local_pose.get_rotation_quaternion())

		# Lowerarm: sin importar cuánto giró el upperarm, termina apuntando
		# derecho hacia abajo (compensa con la rotación total desde su pose real).
		var low_delta := Quaternion(arm_dir, down_dir)
		var low_new_global_basis: Basis = Basis(low_delta) * low_pose.basis
		var low_local_pose: Basis = up_new_global_basis.inverse() * low_new_global_basis
		sweater_skeleton.set_bone_pose_rotation(low_idx, low_local_pose.get_rotation_quaternion())

## Aplica los sliders de "Suéter" (ver @export arriba) a los blend shapes
## horneados en Sueter.glb (Manga_Ancho, Manga_Largo, Cuerpo_Ancho,
## Cuerpo_Largo). Cada blend shape ya trae su desplazamiento máximo horneado
## (en metros, ver MAX_* en el script de extracción); acá solo se mapea el
## slider 0..1 al peso 0..1 del blend shape correspondiente.
func _apply_sweater_fit(sweater_mesh: MeshInstance3D) -> void:
	var mesh: ArrayMesh = sweater_mesh.mesh
	var sliders := {
		"Manga_Ancho": sweater_sleeve_width,
		"Manga_Largo": sweater_sleeve_length,
		"Cuerpo_Ancho": sweater_body_width,
		"Cuerpo_Largo": sweater_body_length,
	}
	for i in mesh.get_blend_shape_count():
		var shape_name := mesh.get_blend_shape_name(i)
		if sliders.has(shape_name):
			sweater_mesh.set_blend_shape_value(i, sliders[shape_name])

var head_attach: BoneAttachment3D

# Estado del resorte de _update_hair_sway(), mandado a todos los materiales
# de pelo por igual.
var hair_sway_mats: Array[ShaderMaterial] = []
var hair_sway_offset: Vector3 = Vector3.ZERO
var hair_sway_velocity: Vector3 = Vector3.ZERO

## Devuelve (creándolo si hace falta) el BoneAttachment3D colgado del hueso
## Head, compartido entre el cabello placeholder y el cabello real (TressFX).
func _get_head_attach() -> BoneAttachment3D:
	if head_attach != null:
		return head_attach
	var head_idx := skeleton.find_bone(&"Head")
	if head_idx == -1:
		return null
	var attach := BoneAttachment3D.new()
	attach.name = "HairAttachment"
	skeleton.add_child(attach)
	attach.bone_name = "Head"
	attach.bone_idx = head_idx
	head_attach = attach
	return attach

## Crea la geometría de cabello (dos esferas simples) colgada del hueso Head
## vía BoneAttachment3D. Se genera en código (no vive en el .tscn) porque el
## Mannequin_F no trae malla de pelo propia.
func _setup_hair() -> void:
	if not hair_enabled:
		return
	var attach := _get_head_attach()
	if attach == null:
		return

	var mat := StandardMaterial3D.new()
	mat.albedo_color = hair_color
	mat.roughness = 0.85

	var top_mesh := SphereMesh.new()
	top_mesh.radius = hair_radius
	top_mesh.height = hair_radius * 2.0
	top_mesh.material = mat
	var top_instance := MeshInstance3D.new()
	top_instance.name = "HairTop"
	top_instance.mesh = top_mesh
	top_instance.position = hair_top_offset
	attach.add_child(top_instance)

	var back_mesh := SphereMesh.new()
	back_mesh.radius = hair_radius * 0.85
	back_mesh.height = hair_radius * 1.7 + hair_back_length
	back_mesh.material = mat
	var back_instance := MeshInstance3D.new()
	back_instance.name = "HairBack"
	back_instance.mesh = back_mesh
	back_instance.position = hair_back_offset
	attach.add_child(back_instance)

## Cuelga el pelo real de TressFX (assets de la demo "ponytail") del hueso
## Head. La demo es rígida (sin skeleton propio) y está armada a escala
## humana con origen en el pecho (cabeza en Y=TRESSFX_HEAD_Y_IN_DEMO); acá se
## re-ancla todo para que el origen quede en el cráneo, y se re-escala con
## hair_radius/hair_tfx_scale. Primera aproximación: ajustá hair_tfx_scale y
## hair_tfx_offset una vez que lo veas correr.
func _setup_tressfx_hair() -> void:
	if not hair_tfx_enabled:
		return
	if not ClassDB.class_exists("TressFXHair"):
		push_warning("TressFX no está cargado todavía: reiniciá el editor una vez (ver addons/tressfx/README.md) y volvé a correr la escena.")
		return
	var attach := _get_head_attach()
	if attach == null:
		return

	var rig := Node3D.new()
	rig.name = "TressFXHairRig"
	rig.position = hair_top_offset + hair_tfx_offset
	var rig_scale: float = (hair_radius / 0.26) * hair_tfx_scale
	rig.scale = Vector3.ONE * rig_scale
	attach.add_child(rig)

	# Colisionadores primitivos (mismas medidas que la demo, reancladas a la cabeza).
	var head_collider := TressFXCollisionMesh.new()
	head_collider.name = "HeadCollider"
	var head_shape := CapsuleMesh.new()
	head_shape.radius = 0.26
	head_shape.height = 0.62
	head_collider.mesh = head_shape
	head_collider.num_cells_x = 48
	head_collider.position = Vector3(0, 0.9 - TRESSFX_HEAD_Y_IN_DEMO, -0.02)
	rig.add_child(head_collider)

	var back_collider := TressFXCollisionMesh.new()
	back_collider.name = "BackCollider"
	var back_shape := SphereMesh.new()
	back_shape.radius = 0.22
	back_shape.height = 0.44
	back_collider.mesh = back_shape
	back_collider.num_cells_x = 40
	back_collider.position = Vector3(0, 0.83 - TRESSFX_HEAD_Y_IN_DEMO, -0.14)
	rig.add_child(back_collider)

	var neck_collider := TressFXCollisionMesh.new()
	neck_collider.name = "NeckCollider"
	var neck_shape := CapsuleMesh.new()
	neck_shape.radius = 0.17
	neck_shape.height = 0.6
	neck_collider.mesh = neck_shape
	neck_collider.num_cells_x = 32
	neck_collider.position = Vector3(0, 0.42 - TRESSFX_HEAD_Y_IN_DEMO, 0)
	rig.add_child(neck_collider)

	var torso_collider := TressFXCollisionMesh.new()
	torso_collider.name = "TorsoCollider"
	var torso_shape := CapsuleMesh.new()
	torso_shape.radius = 0.44
	torso_shape.height = 1.7
	torso_collider.mesh = torso_shape
	torso_collider.num_cells_x = 48
	torso_collider.transform = Transform3D(Basis(Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)), Vector3(0, -0.15 - TRESSFX_HEAD_Y_IN_DEMO, 0))
	rig.add_child(torso_collider)

	var colliders := [head_collider, back_collider, neck_collider, torso_collider]

	# Cuero cabelludo (pelo corto que cubre la cabeza).
	var head_hair_mat := (load("res://addons/tressfx/demo/ponytail_hair_material.tres") as ShaderMaterial).duplicate() as ShaderMaterial
	var head_hair_alpha: float = (head_hair_mat.get_shader_parameter("base_color") as Color).a
	head_hair_mat.set_shader_parameter("base_color", Color(hair_color.r, hair_color.g, hair_color.b, head_hair_alpha))
	head_hair_mat.set_shader_parameter("tip_color", Color(hair_color.r, hair_color.g, hair_color.b, head_hair_alpha))

	var hair_head := TressFXHair.new()
	hair_head.name = "HairHead"
	hair_head.position = Vector3(0, -TRESSFX_HEAD_Y_IN_DEMO, 0)
	hair_head.tfx_path = TRESSFX_DIR + "ponytail_hair_head.tfx"
	hair_head.import_scale = 0.01
	hair_head.num_follow_hairs = 3
	hair_head.tip_separation = 1.0
	hair_head.material = head_hair_mat
	hair_head.local_stiffness = 0.4
	hair_head.global_stiffness = 0.3
	hair_head.global_range = 0.4
	hair_head.length_iterations = 3
	hair_head.damping = 0.2
	hair_head.gravity = 1.0
	rig.add_child(hair_head)
	hair_head.collision_meshes = colliders.map(func(c): return hair_head.get_path_to(c))

	if not hair_tfx_tail_enabled:
		return

	# Cola de caballo (mechón largo que cuelga y se mueve con la física).
	var tail_hair_mat := (load("res://addons/tressfx/demo/ponytail_tail_material.tres") as ShaderMaterial).duplicate() as ShaderMaterial
	var tail_hair_alpha: float = (tail_hair_mat.get_shader_parameter("base_color") as Color).a
	tail_hair_mat.set_shader_parameter("base_color", Color(hair_color.r, hair_color.g, hair_color.b, tail_hair_alpha))
	tail_hair_mat.set_shader_parameter("tip_color", Color(hair_color.r, hair_color.g, hair_color.b, tail_hair_alpha))

	var hair_tail := TressFXHair.new()
	hair_tail.name = "HairTail"
	hair_tail.position = Vector3(0, -TRESSFX_HEAD_Y_IN_DEMO, 0)
	hair_tail.tfx_path = TRESSFX_DIR + "ponytail_hair_tail.tfx"
	hair_tail.import_scale = 0.01
	hair_tail.num_follow_hairs = 3
	hair_tail.tip_separation = 1.0
	hair_tail.material = tail_hair_mat
	hair_tail.vsp_coeff = 0.25
	hair_tail.local_stiffness = 0.35
	hair_tail.global_stiffness = 0.06
	hair_tail.global_range = 0.2
	hair_tail.length_iterations = 3
	hair_tail.damping = 0.1
	hair_tail.gravity = 1.5
	rig.add_child(hair_tail)
	hair_tail.collision_meshes = colliders.map(func(c): return hair_tail.get_path_to(c))

## Cuelga la malla de pelo exportada de VRoid Studio (hinata_hair.tscn) del
## hueso Head. Es geometría estática (no simulada): se reancla con
## VRM_HEAD_OFFSET para que el punto donde VRoid tenía su hueso de cabeza
## quede en el origen del BoneAttachment3D, y de ahí hereda la escala del
## hueso Head (o sea, escala junto con head_scale).
func _setup_toon_hair() -> void:
	if not hair_toon_enabled:
		return
	if not ResourceLoader.exists(HINATA_HAIR_SCENE):
		push_warning("No se encontró " + HINATA_HAIR_SCENE + ": exportá el pelo desde VRoid Studio y volvé a generar la escena.")
		return
	var attach := _get_head_attach()
	if attach == null:
		return

	var hair_scene := load(HINATA_HAIR_SCENE) as PackedScene
	var hair_root := hair_scene.instantiate()
	hair_root.name = "ToonHair"
	hair_root.position = VRM_HEAD_OFFSET + hair_toon_offset
	hair_root.scale = Vector3.ONE * hair_toon_scale
	attach.add_child(hair_root)

	# Configura la física liviana en cada lámina (HairFront/HairBack, mallas
	# continuas): mide su AABB local para que el shader sepa dónde está la
	# raíz (pegada al cráneo, peso 0) y dónde la punta (peso 1, donde más se
	# nota el sway).
	hair_sway_mats.clear()
	for child_name in ["HairFront", "HairBack"]:
		var mi := hair_root.find_child(child_name, true, false) as MeshInstance3D
		if mi == null:
			continue
		var mat := mi.material_override as ShaderMaterial
		if mat == null:
			continue
		var aabb: AABB = mi.mesh.get_aabb()
		mat.set_shader_parameter("_root_y", aabb.position.y + aabb.size.y)
		mat.set_shader_parameter("_tip_range", max(aabb.size.y, 0.001))
		hair_sway_mats.append(mat)

	_setup_eyes(hair_root)

## Acomoda los quads de ojos (EyeRight/EyeLeft, hijos del pelo VRoid) según
## eye_scale/eye_separation/eye_height/eye_forward, sin tocar la malla ni el
## material — solo su transform local dentro de ToonHair.
func _setup_eyes(hair_root: Node) -> void:
	var eye_r := hair_root.find_child("EyeRight", true, false) as MeshInstance3D
	var eye_l := hair_root.find_child("EyeLeft", true, false) as MeshInstance3D
	if eye_r == null or eye_l == null:
		return
	var scale_basis := Basis().scaled(Vector3.ONE * eye_scale)
	eye_r.transform = Transform3D(scale_basis, Vector3(eye_separation * 0.5, eye_height, eye_forward))
	eye_l.transform = Transform3D(scale_basis, Vector3(-eye_separation * 0.5, eye_height, eye_forward))

## Reemplaza el material del cuerpo (superficie "M_Main" del Mannequin_F, que
## incluye piel y cara) por un ShaderMaterial que oscurece a negro/sombra todo
## lo que esté por encima de measured_head_y + face_shadow_offset (VERTEX.y ya
## incluye el escalado de huesos, así que sigue a head_scale/torso_scale). El
## pelo toon tapa casi toda esa zona, dejando expuesta sobre todo la cara.
func _setup_face_shadow() -> void:
	if not face_shadow_enabled:
		return
	var body_mi := mesh.find_child("Mannequin_F", true, false) as MeshInstance3D
	if body_mi == null:
		return
	var original_mat := body_mi.mesh.surface_get_material(0) as BaseMaterial3D
	var shader := load(FACE_SHADOW_SHADER) as Shader
	if shader == null:
		return
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = shader
	if original_mat:
		shader_mat.set_shader_parameter("_albedo_tex", original_mat.albedo_texture)
	shader_mat.set_shader_parameter("_threshold_y", measured_head_y + face_shadow_offset)
	shader_mat.set_shader_parameter("_softness", face_shadow_softness)
	shader_mat.set_shader_parameter("_shadow_color", Vector3(face_shadow_color.r, face_shadow_color.g, face_shadow_color.b))
	shader_mat.set_shader_parameter("_fresnel_strength", face_shadow_fresnel)
	shader_mat.set_shader_parameter("_body_color", Vector3(body_color.r, body_color.g, body_color.b))
	body_mi.set_surface_override_material(0, shader_mat)

	# Superficie 1 (M_Joints: uniones/costuras) no pasa por el shader de
	# sombra facial (queda fuera de la cara); se tiñe aparte, duplicando el
	# material original para no pisar el recurso compartido del .glb.
	if body_mi.mesh.get_surface_count() > 1:
		var joints_mat := body_mi.mesh.surface_get_material(1)
		if joints_mat is BaseMaterial3D:
			var joints_override := (joints_mat as BaseMaterial3D).duplicate() as BaseMaterial3D
			joints_override.albedo_color = joints_color
			body_mi.set_surface_override_material(1, joints_override)

## Resorte inercial liviano para las láminas de pelo: el "target" es un
## desplazamiento hacia atrás/al costado proporcional a la velocidad
## horizontal local del personaje (relativa a hacia dónde mira, para que
## girar la cámara no mueva el pelo). Un spring-damper clásico
## (accel = (target - offset) * response - velocidad * damping) hace que el
## pelo "se quede atrás" al moverse y vuelva a su lugar con un rebote suave.
## El shader se encarga de amplificar esto hacia las puntas del mechón.
func _update_hair_sway(delta: float) -> void:
	if not hair_sway_enabled or hair_sway_mats.is_empty():
		return
	var cam_basis := camera_pivot.global_transform.basis
	var local_vel := Vector3(cam_basis.x.dot(velocity), 0.0, cam_basis.z.dot(velocity))
	var target := Vector3(-local_vel.x, 0.0, -local_vel.z) * hair_sway_strength
	target = target.limit_length(hair_sway_max)

	var accel := (target - hair_sway_offset) * hair_sway_response - hair_sway_velocity * hair_sway_damping
	hair_sway_velocity += accel * delta
	hair_sway_offset += hair_sway_velocity * delta
	hair_sway_offset = hair_sway_offset.limit_length(hair_sway_max)

	for mat in hair_sway_mats:
		mat.set_shader_parameter("_sway_offset", hair_sway_offset)

## Mide el esqueleto YA escalado (huesos "Head" y "ball_l" en pose global,
## que ya reflejan los set_bone_pose_scale de arriba) y usa esa altura real
## para sincronizar la cápsula de colisión y la altura de la cámara. Sin esto,
## la colisión (fija en el .tscn) y la cámara (pivote a altura fija) quedan
## calibradas para el Mannequin original y el personaje "flota" o se hunde
## en cuanto las proporciones cambian.
func _sync_body_to_proportions() -> void:
	var head_idx := skeleton.find_bone(&"Head")
	# "foot_l" es el hueso del TOBILLO (queda ~0.10m por encima del piso real
	# en la pose original) — usarlo como referencia de suelo hundía la suela
	# visual en el piso. "ball_l" (la punta/bola del pie) está a solo ~0.015m
	# del suelo real (verificado contra el AABB de la malla en bind pose),
	# así que es una referencia de "piso" mucho más fiel.
	var ground_idx := skeleton.find_bone(&"ball_l")
	if ground_idx == -1:
		ground_idx = skeleton.find_bone(&"foot_l")
	if head_idx == -1 or ground_idx == -1:
		return

	var head_pos: Vector3 = skeleton.get_bone_global_pose(head_idx).origin
	var ground_pos: Vector3 = skeleton.get_bone_global_pose(ground_idx).origin
	measured_head_y = head_pos.y
	# No hay hueso en la coronilla: se agrega un margen proporcional al tamaño
	# de cabeza para aproximar el punto más alto real de la silueta.
	var head_top_margin: float = 0.12 * head_scale
	var measured_height: float = max((head_pos.y - ground_pos.y) + head_top_margin, 0.4)

	# Encoger las piernas (leg_scale/shin_*) acerca el pie a la cadera, pero la
	# cadera no baja sola: sin esto, el pie visual queda flotando por encima
	# del origen del Player (donde la colisión asume que están los pies).
	# Se reposiciona todo el mesh para que la suela (ball_l) vuelva a tocar y=0.
	mesh.position.y = -ground_pos.y

	stand_height = measured_height
	crouch_height = max(measured_height * 0.55, 0.3)

	var shape := collision_shape.shape as CapsuleShape3D
	shape.radius = clamp(0.4 * ((torso_scale + shoulder_width_scale) * 0.5), 0.15, 0.6)
	_set_crouch(is_crouching)

	# Cámara a la altura aproximada de los ojos (un poco por debajo de la coronilla).
	camera_pivot.position.y = measured_height * 0.92

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mouse_event := event as InputEventMouseMotion
		camera_pivot.rotate_y(-mouse_event.relative.x * mouse_sensitivity)
		var new_pitch: float = spring_arm.rotation.x - mouse_event.relative.y * mouse_sensitivity
		spring_arm.rotation.x = clamp(new_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseButton and event.pressed:
		var wheel_event := event as InputEventMouseButton
		if wheel_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			spring_arm.spring_length = clamp(spring_arm.spring_length - zoom_speed, zoom_min, zoom_max)
		elif wheel_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			spring_arm.spring_length = clamp(spring_arm.spring_length + zoom_speed, zoom_min, zoom_max)
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_SPACE:
			_on_jump_key_pressed()

func _on_jump_key_pressed() -> void:
	if is_on_floor():
		if jump_pending:
			# Llegó un segundo toque a tiempo: cancela el salto pendiente y hace dash.
			jump_pending = false
			_start_dash()
		else:
			# Primer toque: espera un poco por si viene un segundo toque (dash).
			jump_pending = true
			jump_pending_timer = double_tap_window
	else:
		jump_requested = true

func _start_dash() -> void:
	dash_dir = _get_facing_direction()
	is_dashing = true
	dash_timer = dash_duration
	roll_anim_timer = roll_anim_duration

func _get_facing_direction() -> Vector3:
	var forward := -camera_pivot.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := camera_pivot.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()

	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir += forward
	if Input.is_key_pressed(KEY_S):
		dir -= forward
	if Input.is_key_pressed(KEY_A):
		dir -= right
	if Input.is_key_pressed(KEY_D):
		dir += right

	if dir.length() > 0.001:
		return dir.normalized()
	# Sin input de movimiento: usa hacia donde mira el personaje.
	return Vector3(sin(mesh.rotation.y), 0.0, cos(mesh.rotation.y))

func _play_anim(anim_name: StringName, blend_time: float = ANIM_BLEND_TIME, force: bool = false, speed: float = 1.0) -> void:
	if anim_player.has_animation(anim_name) and (force or anim_player.current_animation != anim_name):
		anim_player.play(anim_name, blend_time, speed)



func _set_crouch(crouching: bool) -> void:
	is_crouching = crouching
	var shape := collision_shape.shape as CapsuleShape3D
	if crouching:
		shape.height = crouch_height
		collision_shape.position.y = crouch_height * 0.5
	else:
		shape.height = stand_height
		collision_shape.position.y = stand_height * 0.5

func _physics_process(delta: float) -> void:
	if roll_anim_timer > 0.0:
		roll_anim_timer -= delta
	if landing_timer > 0.0:
		landing_timer -= delta

	if is_dashing:
		dash_timer -= delta
		velocity.x = dash_dir.x * dash_speed
		velocity.z = dash_dir.z * dash_speed
		velocity.y = 0.0
		_play_anim(ANIM_ROLL)
		if dash_timer <= 0.0:
			is_dashing = false
		move_and_slide()
		prev_on_floor = is_on_floor()
		_update_hair_sway(delta)
		return

	var floor_now := is_on_floor()

	# Detectar transiciones piso <-> aire para la máquina de estados de salto.
	if prev_on_floor and not floor_now:
		_play_anim(ANIM_JUMP_START, 0.1, true)
	elif not prev_on_floor and floor_now:
		if Input.is_key_pressed(KEY_CTRL):
			# Jump_Land ya trae su propia flexión de rodillas; encadenarla con
			# Crouch_Idle/Fwd (que vuelve a bajar) se veía como "agacharse dos
			# veces". Si ya venías con Ctrl, se salta Jump_Land directo a la
			# pose de agachado: una sola flexión, no dos.
			landing_timer = 0.0
			_set_crouch(true)
		elif Input.is_key_pressed(KEY_SHIFT):
			# Mismo criterio que con Ctrl: acelerar Jump_Land no alcanzaba,
			# seguía viéndose la flexión de aterrizaje antes de arrancar a
			# correr. Si ya venías con Shift, se salta Jump_Land directo: la
			# selección de animación de más abajo entra en Sprint sola en
			# cuanto landing_timer queda en 0.
			landing_timer = 0.0
		else:
			landing_timer = landing_duration
			# Se fija el ratio de desbloqueo UNA sola vez, con las teclas de
			# ESTE instante (ninguna presionada, ya que si no habríamos entrado
			# en alguna de las dos ramas de arriba). Si se recalculara cada
			# frame en base al estado actual de Shift, presionarlo a mitad de
			# la animación (ya reproduciéndose a velocidad normal) desbloqueaba
			# el movimiento antes de tiempo, desincronizado con la animación.
			landing_recovery_ratio = landing_lock_ratio
			_play_anim(ANIM_JUMP_LAND, 0.1, true)

	if floor_now:
		velocity.y = 0.0
		jumps_used = 0
	else:
		velocity.y -= gravity * gravity_scale * delta
		velocity.y = max(velocity.y, -max_fall_speed)
		if jumps_used >= max_jumps and velocity.y < 0.0 and Input.is_key_pressed(KEY_SPACE):
			velocity.y = max(velocity.y, -glide_fall_speed)

	if jump_pending:
		jump_pending_timer -= delta
		if jump_pending_timer <= 0.0:
			# No llegó segundo toque a tiempo: se confirma como salto normal.
			jump_pending = false
			jump_requested = true

	if jump_requested:
		jump_requested = false
		if jumps_used < max_jumps:
			velocity.y = jump_velocity
			jumps_used += 1
			_play_anim(ANIM_JUMP_START, 0.1, true)

	# Agacharse: solo en el piso y fuera de un roll; cancela el sprint.
	var wants_crouch := Input.is_key_pressed(KEY_CTRL) and floor_now and not is_dashing
	if wants_crouch != is_crouching:
		_set_crouch(wants_crouch)

	var forward := -camera_pivot.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := camera_pivot.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()

	var input_vec := Vector3.ZERO
	# Mientras dura la animación de aterrizaje (landing_timer > 0) se ignora el
	# input de movimiento: antes el personaje ya salía caminando/corriendo a
	# mitad de Jump_Land, sin ni terminar de "asentarse" en el piso.
	var movement_locked := landing_lock_enabled and landing_timer > landing_duration * (1.0 - landing_recovery_ratio)
	if not movement_locked:
		if Input.is_key_pressed(KEY_W):
			input_vec += forward
		if Input.is_key_pressed(KEY_S):
			input_vec -= forward
		if Input.is_key_pressed(KEY_A):
			input_vec -= right
		if Input.is_key_pressed(KEY_D):
			input_vec += right

	var target_speed := walk_speed
	if is_crouching:
		target_speed = crouch_speed
	elif floor_now and Input.is_key_pressed(KEY_SHIFT):
		# floor_now: Shift solo acelera a velocidad de sprint en el piso. Sin
		# esto, mantener Shift en el aire ya aceleraba el movimiento horizontal
		# a velocidad de correr antes de aterrizar, aunque la animación
		# siguiera siendo de salto/caída (se sentía "adelantado").
		target_speed = run_speed

	if input_vec.length() > 0.001:
		input_vec = input_vec.normalized()
		velocity.x = move_toward(velocity.x, input_vec.x * target_speed, acceleration * delta * target_speed)
		velocity.z = move_toward(velocity.z, input_vec.z * target_speed, acceleration * delta * target_speed)
		var target_rot := atan2(input_vec.x, input_vec.z)
		mesh.rotation.y = lerp_angle(mesh.rotation.y, target_rot, rotation_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta * walk_speed)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta * walk_speed)

	move_and_slide()
	prev_on_floor = floor_now
	_update_hair_sway(delta)

	if roll_anim_timer > 0.0:
		# El dash físico ya terminó pero el roll sigue jugándose hasta completarse,
		# aunque el jugador ya haya recuperado el control del movimiento.
		_play_anim(ANIM_ROLL)
	elif landing_timer > 0.0:
		_play_anim(ANIM_JUMP_LAND, 0.1)
	elif not floor_now:
		# Jump_Start ya se disparó en la transición; una vez termina, se
		# mantiene en Jump_Loop hasta aterrizar.
		if anim_player.current_animation == ANIM_JUMP_START and anim_player.is_playing():
			pass
		else:
			_play_anim(ANIM_JUMP_LOOP)
	elif is_crouching:
		if input_vec.length() > 0.001:
			_play_anim(ANIM_CROUCH_FWD)
		else:
			_play_anim(ANIM_CROUCH_IDLE)
	elif input_vec.length() > 0.001:
		if Input.is_key_pressed(KEY_SHIFT):
			_play_anim(ANIM_RUN)
		else:
			_play_anim(ANIM_WALK)
	else:
		_play_anim(ANIM_IDLE)
