class_name PlayerIK
extends Node
# ===========================================================================
#  MAPA DEL ARCHIVO  (todos los números ajustables están en GaitTuning.gd)
#  setup / _make_limb ........ crea huesos, límites y los 5 modificadores
#  _phase_legs ............... [1] pies, cadera y piernas   (GaitTuning: Pies, Cadera, Umbrales)
#  _phase_torso .............. [2] torso, hombros, respiración (Torso y hombros, Reposo)
#  _phase_arms ............... [3] brazos pendulares y manos en pared (Brazos)
#  _phase_head ............... [4] cabeza hacia la cámara   (Cabeza)
#  _phase_limits ............. [5] límites articulares      (Límites articulares)
#  _step_legs ................ máquina de pasos: cuándo y dónde da cada pie su paso (Cadencia y zancada)
#  _foot_pitch / _proc_foot_target ... pisada talón-planta-punta y objetivo del pie
#  _roll_stop_style / _comfort_goal .. cómo queda parado (postura de parada)
#  _pelvis_twist / _torso_motion / _swing_arms / _solve_head ... el movimiento en sí
#  _solve_two_bone ........... IK analítica de 2 huesos (rodilla/codo)
# ===========================================================================
## Cinemática inversa (IK) del personaje, por código sobre el Skeleton3D de
## Player (no toca ningún .tscn). Solver propio de dos huesos + mirada de
## cabeza, ejecutado como SkeletonModifier3D (después de la animación).
##
## - PIES: cada pierna (thigh -> calf -> foot). Un raycast hacia abajo desde
##   cada pie mide el piso real y el pie se apoya en escalones/rampas
##   (±tune.foot_max_offset). El pie conserva su orientación (queda plano).
## - MANOS: cada brazo (upperarm -> lowerarm -> hand). Si el personaje está
##   casi quieto y hay una pared delante (< tune.hand_reach_distance) las
##   manos se apoyan en ella.
## - CABEZA: el hueso Head gira hacia donde apunta la cámara, con límite de
##   yaw/pitch respecto al cuerpo y suavizado.
##
## Cada parte tiene un peso que sube/baja solo; con peso 0 queda la
## animación pura (en el aire, rodando, dash, etc.).

## Animaciones durante las cuales los pies usan pasos procedurales.
const PROC_ANIMS: Array[StringName] = [&"Idle", &"Walk"]

const LEFT := "_l"
const RIGHT := "_r"

var player: CharacterBody3D
var tune: GaitTuning              # TODAS las constantes (scripts/GaitTuning.gd)
var skeleton: Skeleton3D
var modifiers: Array[SkeletonModifier3D] = []
var legs := {}   # side -> Limb
var arms := {}   # side -> Limb

var head_idx := -1
var pelvis_idx := -1
var pelvis_drop := 0.0
var head_fwd_local := Vector3.BACK   # eje del hueso Head que mira "adelante" (auto)
var head_weight := 0.0
var gait_s := 0.0                # -1..1: pierna izq adelante (+) / der adelante (-)
var gait_dir := Vector3.BACK     # dirección de avance (mundo, horizontal)
var body_w := 0.0                # peso de la coordinación de cuerpo completo
var sway_s := 0.0                # desplazamiento lateral suavizado de la cadera (m)
var swing_q := 0.0               # -1..1: pierna izq (+) / der (-) en el aire
var idle_w := 0.0                # peso de la "vida" en reposo (respiración, balanceo)
var arm_w := 0.0                 # peso del vaivén de brazos (decae al parar)
var arm_th := {"_l": 0.0, "_r": 0.0}   # ángulo de cada brazo (rad, + = adelante)
var arm_om := {"_l": 0.0, "_r": 0.0}
var arm_el := {"_l": 0.0, "_r": 0.0}   # flexión del codo
var arm_el_om := {"_l": 0.0, "_r": 0.0}
var ts := {"yaw": 0.0, "yaw_v": 0.0, "roll": 0.0, "roll_v": 0.0, "pitch": 0.0, "pitch_v": 0.0}   # resortes del torso
var prev_vel := Vector3.ZERO
var prev_face_yaw := 0.0
var turn_s := 0.0
var next_foot := "_l"            # pie que da el próximo paso (se alternan siempre)
var step_timer := 0.0
var stop_pending := false        # se movía y aún no se sorteó la postura final
# Zona de comodidad de cada pie respecto a su cadera al parar (se sortea en cada parada).
# Un pie que ya está dentro NO se mueve; uno que está fuera solo vuelve hasta el borde.
var last_move_speed := 0.0       # velocidad que llevaba justo antes de soltar la flecha
var stop_style := "juntos"       # estilo de postura de parada elegido (depuración)
var step_interval := 0.3
var moving_state := false        # ya arrancó la marcha (para el primer paso rápido)
var lean_smooth := 0.0
var head_dir_smooth := Vector3.ZERO  # dirección de mirada suavizada (mundo)

class Limb:
	var root := -1
	var mid := -1
	var end := -1
	var weight := 0.0
	var offset_y := 0.0           # (pies) desplazamiento vertical suavizado
	var goal := Vector3.ZERO      # (manos) punto de pared deseado (mundo)
	var target := Vector3.ZERO    # objetivo actual (mundo)
	var pole := Vector3.ZERO      # hacia dónde apunta el codo/rodilla (mundo)
	# --- pasos procedurales (piernas) ---
	var pw := 0.0                 # peso del modo procedural (0 = animación, 1 = pasos propios)
	var pinit := false
	var planted := Vector3.ZERO   # punto donde está apoyado el pie (mundo, xz válidos)
	var swinging := false
	var swing_t := 0.0
	var swing_dur := 0.25
	var swing_from := Vector3.ZERO
	var stance_t := 0.0             # segundos desde que el pie aterrizó
	var pitch_s := 0.0              # inclinación del pie suavizada (+ = punta arriba)
	var idle_goal := Vector3.ZERO   # destino de un paso hecho estando quieto
	# zona de comodidad del pie al parar, respecto a su cadera (m); + adelante / + hacia afuera
	var zf_min := -0.08
	var zf_max := 0.08
	var zl_min := 0.0
	var zl_max := 0.06
	var step_mul := 1.0             # variación del largo de este paso
	var lift_mul := 1.0             # variación de la altura de este paso
	var lat_off := 0.0              # desvío lateral (m) del aterrizaje de este paso
	var step_yaw := 0.0             # giro del pie en este paso (rad)
	var yaw_goal := 0.0             # giro extra del pie al parar (rad, aleatorio)
	var yaw_jit := 0.0              # giro extra suavizado
	var land_s := Vector3.ZERO      # destino de aterrizaje suavizado (evita tirones al soltar/retomar la tecla)
	var swing_pos := Vector3.ZERO
	var ankle_h := 0.07           # altura del tobillo sobre el piso en reposo
	var rest_rel := Basis.IDENTITY  # rotación del pie en reposo relativa al mesh
	var measured := false
	var flat_rot_skel := Basis.IDENTITY
	var use_flat := false

func setup(p_player: CharacterBody3D, p_skeleton: Skeleton3D) -> void:
	player = p_player
	tune = player.ik_tuning if player.ik_tuning != null else GaitTuning.new()
	skeleton = p_skeleton
	name = "PlayerIK"
	for side in [LEFT, RIGHT]:
		legs[side] = _make_limb("thigh" + side, "calf" + side, "foot" + side)
		arms[side] = _make_limb("upperarm" + side, "lowerarm" + side, "hand" + side)
	head_idx = skeleton.find_bone(&"Head")
	pelvis_idx = skeleton.find_bone(&"pelvis")
	if head_idx != -1:
		_auto_head_axis()
	# Orden de ejecución = orden de hijos: piernas/cadera -> torso -> brazos -> cabeza
	for ph in [[Phase.LEGS, "IK_Piernas"], [Phase.TORSO, "IK_Torso"], [Phase.ARMS, "IK_Brazos"], [Phase.HEAD, "IK_Cabeza"], [Phase.LIMITS, "IK_Limites"]]:
		var m := IKModifier.new()
		m.name = ph[1]
		m.phase = ph[0]
		m.ik = self
		skeleton.add_child(m)
		modifiers.append(m)

func _make_limb(root: String, mid: String, end: String) -> Limb:
	var limb := Limb.new()
	limb.root = skeleton.find_bone(root)
	limb.mid = skeleton.find_bone(mid)
	limb.end = skeleton.find_bone(end)
	if limb.root == -1 or limb.mid == -1 or limb.end == -1:
		push_warning("PlayerIK: faltan huesos %s/%s/%s." % [root, mid, end])
		return null
	return limb

## Qué eje local del hueso Head apunta hacia adelante del personaje (+Z del
## mesh) en la pose de reposo. Depende del rig, así que se mide.
func _auto_head_axis() -> void:
	var rest := skeleton.get_bone_global_rest(head_idx)
	var b := player.global_basis.inverse() * skeleton.global_basis * rest.basis.orthonormalized()
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var best := -2.0
	for i in 3:
		var col: Vector3 = [b.x, b.y, b.z][i]
		for sign_ in [1.0, -1.0]:
			var d: float = col.normalized().dot(Vector3.BACK) * sign_
			if d > best:
				best = d
				head_fwd_local = axes[i] * sign_

## Un SkeletonModifier3D por parte del cuerpo (diseño de Godot 4.3+): son hijos
## directos del Skeleton3D, corren DESPUÉS del AnimationMixer y en el orden de
## la lista de hijos. Escriben la pose al 100 %; `influence` (mezcla) y `active`
## los maneja el Skeleton3D, y se pueden tocar desde el Inspector.
## La modificación es temporal: el esqueleto vuelve a la pose animada al
## terminar el frame (para leer el resultado usa Skeleton3D.skeleton_updated).
enum Phase { LEGS, TORSO, ARMS, HEAD, LIMITS }

class IKModifier extends SkeletonModifier3D:
	var ik: PlayerIK
	var phase: int = 0
	func _process_modification() -> void:
		if ik != null and ik.player != null:
			ik._run_phase(phase, get_process_delta_time())

# --- contexto compartido por frame (se calcula una sola vez) ---
var c_frame := -1
var c_delta := 0.016
var c_on_floor := false
var c_fwd := Vector3.BACK
var c_right := Vector3.RIGHT
var c_space: PhysicsDirectSpaceState3D
var c_excl: Array[RID] = []
var c_speed := 0.0
var c_k := 0.2
var c_proc_ready := false

func _ctx(delta: float) -> void:
	var f := Engine.get_process_frames()
	if f == c_frame:
		return
	c_frame = f
	c_delta = clampf(delta, 0.0001, 0.1)
	c_on_floor = player.is_on_floor()
	c_fwd = player.mesh.global_basis.z
	c_fwd.y = 0.0
	c_fwd = c_fwd.normalized()
	c_right = c_fwd.cross(Vector3.UP).normalized()   # derecha del personaje
	c_space = player.get_world_3d().direct_space_state
	c_excl = [player.get_rid()]
	c_speed = Vector2(player.velocity.x, player.velocity.z).length()
	c_k = 1.0 - exp(-c_delta * 14.0)

func _run_phase(phase: int, delta: float) -> void:
	_ctx(delta)
	match phase:
		Phase.LEGS: _phase_legs()
		Phase.TORSO: _phase_torso()
		Phase.ARMS: _phase_arms()
		Phase.HEAD: _phase_head()
		Phase.LIMITS: _phase_limits()

func _phase_legs() -> void:
	var delta := c_delta
	var on_floor := c_on_floor
	var fwd := c_fwd
	var right := c_right
	var space := c_space
	var excl := c_excl
	var speed := c_speed
	var k := c_k
	# ---- Pies ----
	# [1] ¿corre la IK de pies? y ¿con pasos propios? (tune: feet, procedural_walk)
	var feet_on: bool = tune.feet and on_floor and not player.is_dashing
	var anim_name: StringName = player.anim_player.current_animation
	var proc_on: bool = tune.procedural_walk and feet_on \
		and PROC_ANIMS.has(anim_name)
	# medir la postura de reposo (una vez) con el personaje quieto en Idle
	if feet_on and anim_name == &"Idle" and speed < 0.05:
		for side in legs:
			var l: Limb = legs[side]
			if l != null and not l.measured:
				var fb := _bone_world(l.end)
				l.ankle_h = fb.origin.y - player.global_position.y
				l.rest_rel = player.mesh.global_basis.orthonormalized().inverse() * (skeleton.global_basis * skeleton.get_bone_global_pose(l.end).basis).orthonormalized()
				# la animación Idle puede dejar el pie girado (el derecho salía ~44° hacia afuera/adentro):
				# se mide hacia dónde apunta la punta (pie -> ball) y se corrige a "mirando al frente"
				# con una ligera apertura natural (~6°, positiva hacia la izquierda del personaje).
				var ball := skeleton.find_bone("ball" + side)
				if ball != -1:
					var inv_m: Transform3D = player.mesh.global_transform.affine_inverse()
					var tf: Vector3 = inv_m * fb.origin
					var tb: Vector3 = inv_m * _bone_world(ball).origin
					var dd := tb - tf
					var yaw_meas := atan2(dd.x, dd.z)
					var toe_out: float = deg_to_rad(tune.toe_out_deg) * (1.0 if side == LEFT else -1.0)
					l.rest_rel = Basis(Vector3.UP, toe_out - yaw_meas) * l.rest_rel
				l.measured = true
	var proc_ready: bool = proc_on and legs[LEFT] != null and legs[RIGHT] != null \
		and (legs[LEFT] as Limb).measured and (legs[RIGHT] as Limb).measured
	if proc_ready:
		_step_legs(delta, fwd, space, excl, speed)

	# objetivos de pie (mundo) ANTES de mover la cadera
	# [2] objetivo de cada pie (mundo) y cuánto debe bajar la cadera para que llegue
	var lowest := 0.0
	var need_drop := 0.0
	for side in legs:
		var leg: Limb = legs[side]
		if leg == null:
			continue
		var foot := _bone_world(leg.end)
		var hip := _bone_world(leg.root)
		var want_off := 0.0
		if feet_on:
			var from := Vector3(foot.origin.x, player.global_position.y + 0.6, foot.origin.z)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.2, tune.collision_mask, excl))
			if hit:
				want_off = clampf(hit.position.y - player.global_position.y,
					-tune.foot_max_offset, tune.foot_max_offset)
				if absf(want_off) < tune.ground_deadband:
					want_off = 0.0   # umbral: los desniveles muy pequeños se ignoran (no es perfecto)
		leg.offset_y = lerpf(leg.offset_y, want_off, k)
		leg.weight = lerpf(leg.weight, 1.0 if feet_on else 0.0, k)
		leg.pw = lerpf(leg.pw, 1.0 if proc_ready else 0.0, k)
		if not proc_ready and leg.pw < 0.02:
			leg.pinit = false
			leg.swinging = false
		var anim_target := foot.origin + Vector3.UP * leg.offset_y
		leg.target = anim_target
		leg.use_flat = false
		if leg.pw > 0.002 and leg.pinit:
			leg.target = anim_target.lerp(_proc_foot_target(leg, space, excl, speed), leg.pw)
			var flat_world: Basis = player.mesh.global_basis.orthonormalized() * leg.rest_rel
			# pisada: talón primero (punta arriba), pie plano, despegue de punta
			var want_pitch := _foot_pitch(leg) if moving_state else 0.0
			leg.pitch_s = lerpf(leg.pitch_s, want_pitch, 1.0 - exp(-delta * tune.foot_pitch_rate))
			leg.yaw_jit = lerpf(leg.yaw_jit, leg.step_yaw if moving_state else leg.yaw_goal, 1.0 - exp(-delta * tune.foot_yaw_rate))
			flat_world = Basis(Vector3.UP, leg.yaw_jit) * flat_world
			flat_world = Basis(right, leg.pitch_s) * flat_world
			leg.flat_rot_skel = skeleton.global_basis.orthonormalized().inverse() * flat_world
			leg.use_flat = true
		leg.pole = hip.origin + fwd * 1.0   # rodilla hacia adelante
		lowest = minf(lowest, leg.offset_y * leg.weight)
		# ¿la pierna llega? si no, la cadera baja lo necesario
		var reach: float = (hip.origin.distance_to(_bone_world(leg.mid).origin) + _bone_world(leg.mid).origin.distance_to(foot.origin)) * 1.0 + tune.foot_tolerance   # tolerancia: no se baja la cadera por faltas pequeñas; el pie queda flotando/patinando un poco
		var hd := Vector2(leg.target.x - hip.origin.x, leg.target.z - hip.origin.z).length()
		var vd := hip.origin.y - leg.target.y
		need_drop = maxf(need_drop, (vd - sqrt(maxf(reach * reach - hd * hd, 0.0))) * leg.weight)
	# la cadera baja lo que baja el pie más bajo / lo que falta para llegar
	var sw_l := sin(PI * clampf((legs[LEFT] as Limb).swing_t, 0.0, 1.0)) if (legs[LEFT] as Limb).swinging else 0.0
	var sw_r := sin(PI * clampf((legs[RIGHT] as Limb).swing_t, 0.0, 1.0)) if (legs[RIGHT] as Limb).swinging else 0.0
	swing_q = lerpf(swing_q, sw_l - sw_r, 1.0 - exp(-delta * tune.swing_q_rate))
	sway_s = lerpf(sway_s, (sw_l - sw_r) * tune.pelvis_sway * tune.looseness * clampf(speed / tune.motion_speed_ref, 0.0, 1.0) * body_w, 1.0 - exp(-delta * tune.sway_rate))
	var ph := 1.0 - clampf(step_timer / maxf(step_interval, 0.1), 0.0, 1.0)
	var bob: float = -(0.5 + 0.5 * cos(TAU * ph)) * tune.pelvis_bob * tune.looseness * clampf(speed / tune.motion_speed_ref, 0.0, 1.0) * body_w   # más baja al pisar, más alta a mitad del paso
	# [3] cadera: rebote, desplazamiento lateral y bajada (tune: grupo Cadera)
	_drop_pelvis(minf(lowest, -clampf(need_drop, 0.0, tune.pelvis_drop_max)) + bob, delta, right * sway_s)
	# ---- Cuerpo completo: torsión de cadera, torso inclinado, brazos ----
	# [4] cuánto entra el movimiento de cuerpo completo y la "vida" en reposo
	body_w = lerpf(body_w, clampf(speed / tune.body_blend_speed, 0.0, 1.0) if proc_ready else 0.0, 1.0 - exp(-delta * tune.body_blend_rate))
	c_proc_ready = proc_ready
	if not proc_ready:
		gait_s = lerpf(gait_s, 0.0, k)
	idle_w = lerpf(idle_w, (1.0 - body_w) if proc_ready else 0.0, 1.0 - exp(-delta * tune.idle_blend_rate))
	_pelvis_twist(speed)
	# [5] resolver las dos piernas (IK de dos huesos hacia leg.target)
	for side in legs:
		var leg: Limb = legs[side]
		if leg != null and leg.weight > 0.002:
			_solve_two_bone(leg, true)

func _phase_torso() -> void:
	_torso_motion(c_speed, c_right, c_delta)

func _phase_arms() -> void:
	var fwd := c_fwd
	var right := c_right
	var space := c_space
	var excl := c_excl
	var speed := c_speed
	var k := c_k
	var on_floor := c_on_floor
	# [3a] vaivén de brazos como péndulo amortiguado (tune: grupo Brazos)
	arm_w = lerpf(arm_w, 1.0 if c_proc_ready else 0.0, 1.0 - exp(-c_delta * tune.arm_blend_rate))
	if arm_w > 0.01:
		_swing_arms(right, speed, c_delta)

	# ---- Manos sobre la pared ----
	# [3b] manos sobre la pared, solo si estás casi quieto frente a ella (tune: hands, hand_*)
	var hands_on: bool = tune.hands and on_floor and speed < tune.hand_idle_speed and not player.is_dashing
	for side in arms:
		var arm: Limb = arms[side]
		if arm == null:
			continue
		var shoulder := _bone_world(arm.root)
		var hand := _bone_world(arm.end)
		var found := false
		if hands_on:
			var from := shoulder.origin
			var reach: float = tune.hand_reach_distance
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				from, from + fwd * reach, tune.collision_mask, excl))
			if hit:
				arm.goal = hit.position + hit.normal * 0.04
				found = true
		arm.weight = lerpf(arm.weight, 1.0 if found else 0.0, k)
		arm.target = hand.origin.lerp(arm.goal, arm.weight)
		var out := right * (1.0 if side == RIGHT else -1.0)
		arm.pole = shoulder.origin - fwd * 0.8 + out * 0.5   # codo atrás y afuera
		if arm.weight > 0.002:
			_solve_two_bone(arm, false)


func _phase_head() -> void:
	var k := c_k
	var fwd := c_fwd
	var right := c_right
	# ---- Cabeza ----
	if head_idx != -1:
		var head_on: bool = tune.head and not player.is_dashing
		head_weight = lerpf(head_weight, tune.head_weight if head_on else 0.0, k)
		if head_weight > 0.002:
			_solve_head(fwd, right, k)

## ---- Límites articulares (rango de movilidad, en grados) ----
## Bisagras (rodilla, codo): solo se flexionan alrededor de su eje X local, hacia
## un lado (no se doblan "hacia atrás"). Rótulas: cajas de Euler (YXZ) simétricas
## en Y/Z porque los lados L/R del rig están espejados. Valores medidos en las 43
## animaciones de UAL1 y ajustados al rango humano. `tune.limit_scale` los ensancha.
func _phase_limits() -> void:
	if not tune.joint_limits:
		return
	var sc: float = maxf(tune.limit_scale, 0.1)
	for bone_name in tune.hinge_limits:
		var idx := skeleton.find_bone(bone_name)
		if idx == -1:
			continue
		var rest_q: Quaternion = skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()
		var rel: Quaternion = rest_q.inverse() * skeleton.get_bone_pose_rotation(idx)
		if rel.w < 0.0:
			rel = -rel
		var ang := 2.0 * atan2(rel.x, rel.w)               # flexión = giro alrededor de X
		var lim: Vector2 = tune.hinge_limits[bone_name]
		var lim_max := lim.y * sc
		if bone_name.begins_with("calf"):
			lim_max = lerpf(lim_max, tune.knee_walk_max_deg * sc, body_w)   # caminando la rodilla no pasa de ~105°
		var clamped := clampf(ang, deg_to_rad(lim.x), deg_to_rad(lim_max))
		if absf(clamped - ang) > 0.0001:
			# rel = swing * twist(X): se cambia solo la parte "twist" (la flexión)
			var swing := rel * Quaternion(Vector3.RIGHT, ang).inverse()
			skeleton.set_bone_pose_rotation(idx, rest_q * (swing * Quaternion(Vector3.RIGHT, clamped)))
	for bone_name in tune.ball_limits:
		var idx := skeleton.find_bone(bone_name)
		if idx == -1:
			continue
		var rest_q: Quaternion = skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()
		var rel := Basis(rest_q.inverse() * skeleton.get_bone_pose_rotation(idx))
		var e := rel.get_euler(EULER_ORDER_YXZ)
		if absf(e.x) > deg_to_rad(tune.gimbal_guard_deg):
			continue    # cerca del gimbal lock: no se toca
		var b: Array = tune.ball_limits[bone_name]
		var ne := Vector3(
			clampf(e.x, deg_to_rad(b[0] * sc), deg_to_rad(b[1] * sc)),
			clampf(e.y, -deg_to_rad(b[2] * sc), deg_to_rad(b[2] * sc)),
			clampf(e.z, -deg_to_rad(b[3] * sc), deg_to_rad(b[3] * sc)))
		if ne.distance_to(e) > 0.0001:
			skeleton.set_bone_pose_rotation(idx, rest_q * Basis.from_euler(ne, EULER_ORDER_YXZ).get_rotation_quaternion())

## Pasos procedurales: cada pie se apoya en el piso y NO se mueve hasta que
## queda atrasado respecto a su cadera; entonces da un paso hacia adelante
## (en la dirección de avance), de a un pie por vez. Quieto, los pies vuelven
## a quedar paralelos bajo las caderas. Reemplaza el ciclo de piernas grabado.
func _step_legs(delta: float, fwd: Vector3, space: PhysicsDirectSpaceState3D, excl: Array[RID], speed: float) -> void:
	var vel := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var dir := vel.normalized() if speed > 0.15 else Vector3.ZERO
	var legL: Limb = legs[LEFT]
	var legR: Limb = legs[RIGHT]
	# --- por pierna: cadencia, vuelo del pie y quién necesita dar un paso ---
	var urgency := {}
	for side in legs:
		var leg: Limb = legs[side]
		var foot := _bone_world(leg.end)
		var hip := _bone_world(leg.root)
		var leg_len := hip.origin.distance_to(_bone_world(leg.mid).origin) + _bone_world(leg.mid).origin.distance_to(foot.origin)
		var half: float = leg_len * clampf(tune.stride_fraction + tune.stride_speed_slope * (maxf(speed, 1.2) - 2.0), tune.stride_min, tune.stride_max)
		# cadencia regular: un paso cada `step_interval`, siempre alternando pies
		# cadencia como en UAL: v = k * f^2  (Walk: 0.58 m/s a 1.5 pasos/s -> k~0.26 para piernas de 0.55 m)
		var k_len := tune.cadence_k * leg_len / tune.ref_leg_length
		# la pierna solo alcanza ~0.37 m de paso (rango de apoyo ±0.2 m): si la velocidad pide
		# más, se sube la cadencia (UAL Walk a 0.58 m/s: 1.5 pasos/s; a 0.9 m/s hacen falta ~2.4)
		var step_max := tune.max_step_length * leg_len / tune.ref_leg_length
		step_interval = clampf(minf(1.0 / sqrt(maxf(speed, 0.3) / k_len), step_max / maxf(speed, 0.3)), tune.step_interval_min, tune.step_interval_max)
		var dur := clampf(tune.swing_fraction * step_interval, tune.swing_min, tune.swing_max)
		var hp := Vector3(hip.origin.x, 0.0, hip.origin.z)
		if not leg.pinit:
			leg.planted = Vector3(foot.origin.x, 0.0, foot.origin.z)
			leg.swinging = false
			leg.pinit = true
		# EN EL AIRE: avanza hacia el punto de aterrizaje (pierna casi recta al llegar)
		if leg.swinging:
			leg.swing_t += delta / leg.swing_dur
			var remaining := maxf(leg.swing_dur * (1.0 - leg.swing_t), 0.0)
			# aterriza con la pierna ESTIRADA: distancia horizontal cadera-pie tal que
			# cadera->tobillo mida casi todo el largo de la pierna (rodilla recta)
			var vd := hip.origin.y + pelvis_drop - (player.global_position.y + leg.ankle_h)
			var r_full: float = leg_len * tune.leg_reach_factor + tune.foot_tolerance * tune.landing_hover   # zancada completa aunque el pie no llegue a tocar
			var ahead_full := sqrt(maxf(r_full * r_full - vd * vd, 0.0))
			var ahead := clampf(ahead_full, tune.landing_ahead_min * half, tune.landing_ahead_max * half) * leg.step_mul
			var land_raw := (hp + vel * remaining + dir * ahead + c_right * leg.lat_off) if dir != Vector3.ZERO else leg.idle_goal
			# el destino cambia de forma continua: si sueltas o retomas la tecla a mitad de un
			# paso, el pie NO salta hacia otro punto (eso era el "trastabilleo")
			leg.land_s = leg.land_s.lerp(land_raw, 1.0 - exp(-delta * tune.landing_follow_rate))
			var land := leg.land_s
			var t := clampf(leg.swing_t, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			leg.swing_pos = leg.swing_from.lerp(land, t)
			if leg.swing_t >= 1.0:
				leg.planted = land
				leg.swinging = false
				leg.stance_t = 0.0
		# APOYADO: el pie queda fijo en el piso; urgency > 0 = le toca dar un paso
		else:
			leg.stance_t += delta
			var rel := leg.planted - hp
			var u := 0.0
			if dir != Vector3.ZERO:
				# seguridad: pie demasiado lejos de su cadera -> paso de emergencia
				if rel.length() > tune.emergency_step_ratio * leg_len:
					u = rel.length() / (tune.emergency_step_ratio * leg_len)
			else:
				# quieto: cada pie solo se recoloca si quedó fuera de su zona de comodidad,
				# y vuelve hasta el borde de la zona (depende de dónde estaba, no del centro)
				var ex := _comfort_goal(leg, side).distance_to(leg.planted)
				if ex > tune.comfort_trigger:
					u = ex / tune.comfort_trigger
			urgency[side] = u
			leg.swing_dur = dur
	# --- decidir qué pie sale ahora: en marcha por temporizador (alterna), quieto por comodidad ---
	if dir == Vector3.ZERO:
		if stop_pending:
			_roll_stop_style()
			stop_pending = false
		moving_state = false
		step_timer = 0.0
		# quieto: un solo paso a la vez, el pie más desalineado
		if not legL.swinging and not legR.swinging:
			var best := ""
			var best_u := 0.0
			for side in urgency:
				if urgency[side] > best_u:
					best_u = urgency[side]
					best = side
			if best != "":
				_start_step(legs[best], best)
	else:
		# en marcha: cadencia por temporizador, pies alternados (sin "saltitos")
		stop_pending = true
		last_move_speed = speed
		step_timer -= delta
		if step_timer <= 0.0 and not (legs[next_foot] as Limb).swinging:
			_start_step(legs[next_foot], next_foot)
			step_timer = step_interval * randf_range(1.0 - tune.step_interval_jitter, 1.0 + tune.step_interval_jitter)
			moving_state = true
		else:
			for side in urgency:
				var lg: Limb = legs[side]
				if urgency[side] >= 1.0 and not lg.swinging and not legL.swinging and not legR.swinging:
					_start_step(lg, side)
	# --- fase de la marcha (para brazos, torso y pelvis) ---
	gait_dir = dir if dir != Vector3.ZERO else fwd
	var hl := _bone_world(legL.root).origin
	var hr := _bone_world(legR.root).origin
	var pl_xz := legL.swing_pos if legL.swinging else legL.planted
	var pr_xz := legR.swing_pos if legR.swinging else legR.planted
	var fl := (pl_xz - Vector3(hl.x, 0.0, hl.z)).dot(gait_dir)
	var fr := (pr_xz - Vector3(hr.x, 0.0, hr.z)).dot(gait_dir)
	var ref := maxf(0.5 * (hl.distance_to(_bone_world(legL.end).origin) + hr.distance_to(_bone_world(legR.end).origin)) * 0.5, 0.05)
	gait_s = lerpf(gait_s, clampf((fl - fr) / ref, -1.0, 1.0), 1.0 - exp(-delta * tune.gait_phase_rate))

## Inclinación del pie (rad, + = punta arriba) según la fase del paso:
## despegue de punta -> vuelo -> aterriza con el TALÓN -> pie plano -> talón sube.
func _foot_pitch(leg: Limb) -> float:
	var toe_off := deg_to_rad(tune.toe_off_deg)
	var strike := deg_to_rad(tune.heel_strike_deg)
	if leg.swinging:
		var t := clampf(leg.swing_t, 0.0, 1.0)
		if t < tune.swing_toe_off_end:
			return lerpf(toe_off, deg_to_rad(tune.swing_flat_deg), t / tune.swing_toe_off_end)
		var u := clampf((t - tune.swing_toe_off_end) / tune.swing_heel_end, 0.0, 1.0)
		return lerpf(deg_to_rad(tune.swing_flat_deg), strike, u * u * (3.0 - 2.0 * u))
	var f := clampf(leg.stance_t / maxf(step_interval * tune.stance_estimate, 0.1), 0.0, 1.0)
	if f < tune.stance_heel_end:
		return lerpf(strike, 0.0, f / tune.stance_heel_end)
	if f < tune.stance_flat_end:
		return 0.0
	return lerpf(0.0, toe_off, (f - tune.stance_flat_end) / (1.0 - tune.stance_flat_end))

## Sortea cómo queda la postura al soltar la flecha: tolerancia, un pie adelantado,
## separación lateral, cuánto se juntan los pies y un pequeño giro de cada pie.
func _roll_stop_style() -> void:
	var legL: Limb = legs[LEFT]
	var legR: Limb = legs[RIGHT]
	if legL == null or legR == null:
		return
	# contexto: cuánto se adelantaba cada pie, a qué velocidad iba, si el piso es desigual
	var fl := _foot_fwd_off(legL)
	var fr := _foot_fwd_off(legR)
	var stag_now := clampf(absf(fl - fr) / tune.stop_stagger_ref, 0.0, 1.0)
	var sp := clampf(last_move_speed / tune.stop_speed_ref, 0.0, 1.0)
	var uneven := clampf(absf(legL.offset_y - legR.offset_y) / tune.stop_uneven_ref, 0.0, 1.0)
	# pesos: toque corto -> juntos; ya iba con zancada o a más velocidad -> intercalados;
	# piso desigual (escalones/rampas) -> abiertos (más estable); a toda velocidad -> abiertos+intercalados
	var w := {
		"juntos": (1.0 - sp) * (1.0 - 0.6 * uneven),
		"intercalados": 0.35 + 1.0 * sp + 1.4 * stag_now,
		"abiertos": 0.25 + 1.2 * uneven + 0.3 * (1.0 - sp),
		"atleta": 0.1 + 0.5 * sp + 0.4 * uneven,
	}
	var total := 0.0
	for k in w:
		total += maxf(w[k], 0.0)
	var r := randf() * total
	stop_style = "juntos"
	for k in w:
		r -= maxf(w[k], 0.0)
		if r <= 0.0:
			stop_style = k
			break
	# el pie que ya iba más adelante queda de pie delantero (lo lógico), salvo a veces
	var lead_left := fl >= fr
	if randf() < 0.15:
		lead_left = not lead_left
	var sc := randf_range(0.8, 1.2)
	for side in legs:
		var l: Limb = legs[side]
		var lead: bool = (side == LEFT) == lead_left
		var out_yaw := 3.0
		match stop_style:
			"juntos":
				l.zf_min = -0.03 * sc; l.zf_max = 0.03 * sc
				l.zl_min = -0.01; l.zl_max = 0.03 * sc
			"abiertos":
				l.zf_min = -0.05 * sc; l.zf_max = 0.05 * sc
				var j := randf_range(0.0, 0.03)
				l.zl_min = 0.07 + j; l.zl_max = 0.14 * sc + j
				out_yaw = 10.0
			"intercalados":
				l.zf_min = (0.07 if lead else -0.16) * sc
				l.zf_max = (0.15 if lead else -0.06) * sc
				l.zl_min = 0.0; l.zl_max = 0.05 * sc
				out_yaw = 5.0
			_: # atleta: abiertos + un pie adelante
				l.zf_min = (0.06 if lead else -0.13) * sc
				l.zf_max = (0.13 if lead else -0.05) * sc
				l.zl_min = 0.05; l.zl_max = 0.12 * sc
				out_yaw = 8.0
		# puntas algo hacia afuera según la apertura (izq = giro +, der = giro -)
		var sgn := 1.0 if side == LEFT else -1.0
		l.yaw_goal = deg_to_rad(sgn * out_yaw * randf_range(0.5, 1.2) + randf_range(-3.0, 3.0))

## Cuánto está el pie por delante de su cadera (m, a lo largo del frente del cuerpo).
func _foot_fwd_off(leg: Limb) -> float:
	var h := _bone_world(leg.root).origin
	var p: Vector3 = leg.land_s if leg.swinging else leg.planted
	return (p - Vector3(h.x, 0.0, h.z)).dot(c_fwd)

## Punto más cercano a `leg.planted` dentro de la zona de comodidad del pie
## (respecto a su cadera). Si el pie ya está dentro, devuelve su posición actual.
func _comfort_goal(leg: Limb, side: String) -> Vector3:
	var h := _bone_world(leg.root).origin
	var rel := leg.planted - Vector3(h.x, 0.0, h.z)
	var sg := 1.0 if side == RIGHT else -1.0
	var f := rel.dot(c_fwd)
	var o := rel.dot(c_right) * sg
	var nf := clampf(f, leg.zf_min, leg.zf_max)
	var no := clampf(o, leg.zl_min, leg.zl_max)
	return leg.planted + c_fwd * (nf - f) + c_right * (no - o) * sg

func _start_step(leg: Limb, side: String) -> void:
	leg.swinging = true
	leg.swing_t = 0.0
	leg.swing_from = leg.planted
	leg.swing_pos = leg.planted
	# estando quieto, el pie vuelve solo hasta el borde de su zona de comodidad
	leg.idle_goal = _comfort_goal(leg, side)
	# variación propia de cada paso (nunca dos iguales); el largo solo se acorta para no sobreextender
	leg.step_mul = randf_range(tune.step_mul_min, tune.step_mul_max)
	leg.lift_mul = randf_range(tune.lift_mul_min, tune.lift_mul_max)
	leg.lat_off = randf_range(-tune.landing_side_jitter, tune.landing_side_jitter)
	leg.step_yaw = deg_to_rad(randf_range(-tune.step_yaw_jitter_deg, tune.step_yaw_jitter_deg))
	leg.land_s = leg.planted
	next_foot = RIGHT if side == LEFT else LEFT
	step_timer = step_interval   # cualquier paso reinicia la cadencia (evita "dobles pasos")

## Objetivo del pie en modo procedural (mundo): apoyado fijo en el piso o en
## el aire siguiendo el arco del paso.
func _proc_foot_target(leg: Limb, space: PhysicsDirectSpaceState3D, excl: Array[RID], speed: float) -> Vector3:
	var xz := leg.swing_pos if leg.swinging else leg.planted
	var from := Vector3(xz.x, player.global_position.y + 0.6, xz.z)
	var gy := player.global_position.y
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.2, tune.collision_mask, excl))
	if hit:
		gy = hit.position.y
		if absf(gy - player.global_position.y) < tune.ground_deadband:
			gy = player.global_position.y
	var lift := 0.0
	if leg.swinging:
		lift = sin(PI * clampf(leg.swing_t, 0.0, 1.0)) * tune.step_height * clampf(tune.step_height_speed_base + speed * tune.step_height_speed_slope, tune.step_height_speed_base, tune.step_height_speed_max) * leg.lift_mul
	var roll := 0.0
	if moving_state:
		roll = leg.ankle_h * tune.ankle_roll * sin(maxf(-leg.pitch_s, 0.0))   # punta como pivote
	return Vector3(xz.x, gy + leg.ankle_h + lift + roll, xz.z)

## Pelvis gira hacia la pierna que va adelante, el torso contra-gira y se
## inclina hacia adelante según la velocidad (la marcha humana real).
## 0 = velocidad de la animación Walk de UAL (~0.6 m/s), 1 = Jog_Fwd (~3.4 m/s).
## Los valores de cada extremo salen de data/ual_locomotion_joints.csv.
func _gt(speed: float) -> float:
	return clampf((speed - tune.ref_walk_speed) / (tune.ref_jog_speed - tune.ref_walk_speed), 0.0, 1.0)

func _t() -> float:
	return Time.get_ticks_msec() * 0.001

## Cadera: gira hacia la pierna que va adelante, se ladea (baja del lado de la
## pierna que está en el aire) y, quieta, respira / carga el peso de un pie a otro.
func _pelvis_twist(speed: float) -> void:
	var lo: float = tune.looseness
	var sf := clampf(speed / tune.motion_speed_ref, 0.0, 1.0)
	var gt := _gt(speed)
	var twist: float = deg_to_rad(tune.pelvis_twist_deg) * lo * gait_s * sf * body_w
	var roll: float = -swing_q * deg_to_rad(lerpf(tune.pelvis_roll_walk_deg, tune.pelvis_roll_jog_deg, gt)) * lo * sf * body_w
	var inv := skeleton.global_basis.orthonormalized().inverse()
	var up_s: Vector3 = inv * Vector3.UP
	var fwd_s: Vector3 = inv * c_fwd
	var pelvis := skeleton.find_bone(&"pelvis")
	if pelvis == -1:
		return
	# reposo: cambio de peso lento (cadera ladeada y girada unos grados)
	var t := _t()
	var idle: float = idle_w * tune.idle_motion
	var shift: float = sin(t * 0.55) * deg_to_rad(tune.idle_shift_deg) * idle
	var yaw_i: float = sin(t * 0.37 + 1.3) * deg_to_rad(tune.idle_yaw_deg) * idle
	var g := skeleton.get_bone_global_pose(pelvis).basis.orthonormalized()
	_apply_global_rot(pelvis, Basis(fwd_s, roll + shift) * Basis(up_s, -twist + yaw_i) * g, 1.0)

## Torso: se inclina hacia adelante, contra-gira y contra-ladea respecto a la
## cadera (hombros nivelados), y respira en reposo.
func _torso_motion(speed: float, right: Vector3, delta: float) -> void:
	var lo: float = tune.looseness
	var sf := clampf(speed / tune.motion_speed_ref, 0.0, 1.0)
	var gt := _gt(speed)
	var twist: float = deg_to_rad(lerpf(tune.spine_yaw_walk_deg, tune.spine_yaw_jog_deg, gt)) * lo * gait_s * sf * body_w   # giro de columna alta (UAL: 3.6° caminando, 33° trotando)
	var roll: float = swing_q * deg_to_rad(lerpf(tune.spine_roll_walk_deg, tune.spine_roll_jog_deg, gt)) * lo * sf * body_w
	var inv := skeleton.global_basis.orthonormalized().inverse()
	var up_s: Vector3 = inv * Vector3.UP
	var fwd_s: Vector3 = inv * c_fwd
	var right_s: Vector3 = inv * right
	var sp1 := skeleton.find_bone(&"spine_01")
	var sp2 := skeleton.find_bone(&"spine_02")
	var sp3 := skeleton.find_bone(&"spine_03")
	var t := _t()
	var idle: float = idle_w * tune.idle_motion
	var breath: float = sin(t * 1.9) * deg_to_rad(tune.breath_deg) * idle              # respiración
	var sway_i: float = -sin(t * 0.55) * deg_to_rad(tune.idle_counter_deg) * idle           # compensa el peso de la cadera
	# --- dinámica del torso: no está fijo a la cadera, es un resorte que se retrasa ---
	var vel := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var acc := ((vel - prev_vel) / maxf(delta, 0.0001)).limit_length(tune.accel_limit)
	prev_vel = vel
	var face_yaw := atan2(c_fwd.x, c_fwd.z)
	var turn_raw := clampf(wrapf(face_yaw - prev_face_yaw, -PI, PI) / maxf(delta, 0.0001), -6.0, 6.0)
	turn_s = lerpf(turn_s, turn_raw, 1.0 - exp(-delta * tune.turn_filter_rate))   # filtrado: el giro inicial hacia donde caminas no debe sacudir el torso
	var turn_rate := clampf(turn_s, -tune.turn_rate_limit, tune.turn_rate_limit)
	prev_face_yaw = face_yaw
	var dyn: float = tune.torso_dynamics
	var pitch_t: float = deg_to_rad(tune.body_lean_deg) * sf * body_w \
		+ deg_to_rad(tune.accel_lean_deg) * acc.dot(c_fwd) * dyn                              # acelera -> se inclina adelante; frena -> atrás
	var roll_t: float = clampf(roll + sway_i \
		- turn_rate * minf(speed, 1.5) * deg_to_rad(tune.turn_lean_deg) * dyn, -deg_to_rad(tune.torso_roll_limit_deg), deg_to_rad(tune.torso_roll_limit_deg))   # se ladea hacia adentro en las curvas
	var yaw_t: float = clampf(twist * tune.spine_yaw_factor - turn_rate * tune.turn_lag * dyn, -deg_to_rad(tune.torso_yaw_limit_deg), deg_to_rad(tune.torso_yaw_limit_deg))   # los hombros se quedan atrás al girar
	var W := tune.torso_spring_w
	var Z := tune.torso_spring_z
	var n := maxi(ceili(delta / 0.008), 1)
	var dt := delta / float(n)
	for i in n:
		for pair in [["pitch", pitch_t], ["roll", roll_t], ["yaw", yaw_t]]:
			var key: String = pair[0]
			var v: float = ts[key + "_v"]
			var x: float = ts[key]
			v += (W * W * (float(pair[1]) - x) - 2.0 * Z * W * v) * dt
			x += v * dt
			ts[key + "_v"] = v
			ts[key] = x
	lean_smooth = ts["pitch"]
	if sp1 != -1:
		var g1 := skeleton.get_bone_global_pose(sp1).basis.orthonormalized()
		_apply_global_rot(sp1, Basis(right_s, -float(ts["pitch"])) * g1, 1.0)
	if sp2 != -1:
		var g2 := skeleton.get_bone_global_pose(sp2).basis.orthonormalized()
		_apply_global_rot(sp2, Basis(fwd_s, float(ts["roll"])) * Basis(right_s, -breath) * g2, 1.0)
	if sp3 != -1:
		var g3 := skeleton.get_bone_global_pose(sp3).basis.orthonormalized()
		_apply_global_rot(sp3, Basis(up_s, float(ts["yaw"])) * g3, 1.0)
	# hombros: suben/bajan y giran un poquito al ritmo del paso
	var sh_roll: float = swing_q * deg_to_rad(tune.shoulder_roll_deg) * lo * sf * body_w
	var sh_yaw: float = gait_s * deg_to_rad(tune.shoulder_yaw_deg) * lo * sf * body_w
	for side in [LEFT, RIGHT]:
		var ci := skeleton.find_bone("clavicle" + side)
		if ci == -1:
			continue
		var sgn: float = -1.0 if side == LEFT else 1.0
		var gc := skeleton.get_bone_global_pose(ci).basis.orthonormalized()
		_apply_global_rot(ci, Basis(fwd_s, sgn * sh_roll) * Basis(up_s, sh_yaw) * gc, 1.0)

## Brazos opuestos a las piernas: el brazo del lado de la pierna que va atrás
## va adelante. Reemplaza el vaivén de brazos grabado mientras se camina.
func _swing_arms(right: Vector3, speed: float, delta: float) -> void:
	var amp: float = deg_to_rad(tune.arm_swing_deg) * tune.looseness * clampf(speed / tune.arm_speed_ref, 0.0, 1.3)
	var inv := skeleton.global_basis.orthonormalized().inverse()
	# Cada brazo es un péndulo amortiguado que "persigue" el ritmo de las
	# piernas: va con retraso, frena suavemente en los extremos y, al parar,
	# se balancea un poco más y se queda quieto (no sigue al paso como un metrónomo).
	var W := tune.arm_spring_w     # frecuencia natural del brazo (rad/s)
	var Z := tune.arm_spring_z     # amortiguación
	var WE := tune.elbow_spring_w  # codo
	var ZE := tune.elbow_spring_z
	var n := maxi(ceili(delta / 0.008), 1)
	var dt := delta / float(n)
	for i in n:
		for side in arms:
			var sgn := -1.0 if side == LEFT else 1.0
			var tgt: float = sgn * gait_s * amp
			var th: float = arm_th[side]
			var om: float = arm_om[side]
			om += (W * W * (tgt - th) - 2.0 * Z * W * om) * dt
			th += om * dt
			arm_th[side] = th
			arm_om[side] = om
			var etgt: float = deg_to_rad(lerpf(tune.elbow_walk_deg, tune.elbow_jog_deg, _gt(speed))) + deg_to_rad(tune.elbow_swing_deg) * sin(th)
			var el: float = arm_el[side]
			var eom: float = arm_el_om[side]
			eom += (WE * WE * (etgt - el) - 2.0 * ZE * WE * eom) * dt
			el += eom * dt
			arm_el[side] = el
			arm_el_om[side] = eom
	for side in arms:
		var arm: Limb = arms[side]
		if arm == null or arm.weight > 0.05:
			continue
		var theta: float = arm_th[side]
		var bend: float = arm_el[side]
		var out := right * (1.0 if side == RIGHT else -1.0)
		var up_dir: Vector3 = (Vector3.DOWN * cos(theta) + gait_dir * sin(theta) + out * tune.arm_out * tune.looseness).normalized()
		var low_dir := (up_dir * cos(bend) + gait_dir * sin(bend)).normalized()
		var root_g := skeleton.get_bone_global_pose(arm.root)
		var cur_up := (skeleton.get_bone_global_pose(arm.mid).origin - root_g.origin).normalized()
		var q1 := Quaternion(cur_up, (inv * up_dir).normalized())
		_apply_global_rot(arm.root, Basis(q1) * root_g.basis.orthonormalized(), arm_w)
		var mid_g := skeleton.get_bone_global_pose(arm.mid)
		var cur_low := (skeleton.get_bone_global_pose(arm.end).origin - mid_g.origin).normalized()
		var q2 := Quaternion(cur_low, (inv * low_dir).normalized())
		_apply_global_rot(arm.mid, Basis(q2) * mid_g.basis.orthonormalized(), arm_w)

## Baja el hueso pelvis `drop` metros (negativo = baja) en mundo, suavizado.
func _drop_pelvis(drop: float, delta: float = 1.0 / 60.0, sway: Vector3 = Vector3.ZERO) -> void:
	if pelvis_idx == -1:
		return
	pelvis_drop = lerpf(pelvis_drop, drop, 1.0 - exp(-delta * tune.pelvis_drop_rate))
	if absf(pelvis_drop) < 0.0005 and sway.length() < 0.0005:
		return
	var parent := skeleton.get_bone_parent(pelvis_idx)
	var parent_basis := Basis.IDENTITY
	if parent != -1:
		parent_basis = skeleton.get_bone_global_pose(parent).basis
	var down_skel: Vector3 = skeleton.global_basis.inverse() * (Vector3.UP * pelvis_drop + sway)
	var local: Vector3 = parent_basis.inverse() * down_skel
	skeleton.set_bone_pose_position(pelvis_idx, skeleton.get_bone_pose_position(pelvis_idx) + local)

func _bone_world(idx: int) -> Transform3D:
	return skeleton.global_transform * skeleton.get_bone_global_pose(idx)

## Rota `idx` (en espacio de esqueleto) para que su rotación global sea
## `new_global_rot` y escribe la rotación local mezclada con el peso.
func _apply_global_rot(idx: int, new_global_rot: Basis, weight: float) -> void:
	var parent := skeleton.get_bone_parent(idx)
	var parent_rot := Basis.IDENTITY
	if parent != -1:
		parent_rot = skeleton.get_bone_global_pose(parent).basis.orthonormalized()
	var local_q := (parent_rot.inverse() * new_global_rot).get_rotation_quaternion()
	var cur_q := skeleton.get_bone_pose_rotation(idx)
	skeleton.set_bone_pose_rotation(idx, cur_q.slerp(local_q, weight))

## Anti-entrelazado: el objetivo de un pie/mano no puede cruzar la línea media
## del cuerpo (pelvis, eje izq-der de las caderas) más allá de un margen.
## Piernas: ni siquiera la tocan (+3 cm); brazos: pueden cruzar hasta 12 cm.
## `T` y el resultado están en espacio de esqueleto.
func _limit_cross_midline(limb: Limb, T: Vector3) -> Vector3:
	var ll: Limb = legs.get(LEFT)
	var lr: Limb = legs.get(RIGHT)
	if ll == null or lr == null or pelvis_idx == -1:
		return T
	var hl := skeleton.get_bone_global_pose(ll.root).origin
	var hr := skeleton.get_bone_global_pose(lr.root).origin
	var axis := hr - hl                       # de izquierda a derecha
	if axis.length() < 0.001:
		return T
	axis = axis.normalized()
	var center := (hl + hr) * 0.5
	var is_right: bool = (limb == legs.get(RIGHT)) or (limb == arms.get(RIGHT))
	var sgn := 1.0 if is_right else -1.0
	var is_leg: bool = (limb == ll) or (limb == lr)
	var min_lat := 0.03 if is_leg else -0.12
	var lat := (T - center).dot(axis) * sgn
	if lat < min_lat:
		T += axis * sgn * (min_lat - lat)
	return T

## IK analítica de dos huesos (root -> mid -> end) hacia limb.target con el
## codo/rodilla orientado hacia limb.pole. Todo en espacio de esqueleto.
func _solve_two_bone(limb: Limb, keep_end_rotation: bool) -> void:
	var inv := skeleton.global_transform.affine_inverse()
	var T: Vector3 = inv * limb.target
	var P: Vector3 = inv * limb.pole
	var w := limb.weight

	var root_g := skeleton.get_bone_global_pose(limb.root)
	var mid_g := skeleton.get_bone_global_pose(limb.mid)
	var end_g := skeleton.get_bone_global_pose(limb.end)
	var A := root_g.origin
	var B := mid_g.origin
	var C := end_g.origin
	var end_rot := end_g.basis.orthonormalized()
	if limb.use_flat:
		end_rot = Basis(Quaternion(end_rot).slerp(Quaternion(limb.flat_rot_skel), limb.pw))
	var l1 := A.distance_to(B)
	var l2 := B.distance_to(C)
	if l1 < 0.001 or l2 < 0.001:
		return

	if tune.joint_limits:
		T = _limit_cross_midline(limb, T)
	var to_t := T - A
	var d := clampf(to_t.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	if to_t.length() < 0.0001:
		return
	var u := to_t.normalized()
	var pv := P - A
	pv -= u * pv.dot(u)
	if pv.length() < 0.0001:
		pv = (B - A) - u * (B - A).dot(u)
	pv = pv.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var B2 := A + u * a + pv * h
	var T2 := A + u * d   # objetivo alcanzable

	# 1) rotar root para que A->B apunte a A->B2
	var q1 := Quaternion((B - A).normalized(), (B2 - A).normalized())
	_apply_global_rot(limb.root, Basis(q1) * root_g.basis.orthonormalized(), w)

	# 2) con root ya rotado (parcial según peso: se resuelve con peso pleno
	# internamente para que mid use las posiciones finales), rotar mid para
	# que B->C apunte a B->T2.
	var mid2 := skeleton.get_bone_global_pose(limb.mid)
	var end2 := skeleton.get_bone_global_pose(limb.end)
	var q2 := Quaternion((end2.origin - mid2.origin).normalized(), (T2 - mid2.origin).normalized())
	_apply_global_rot(limb.mid, Basis(q2) * mid2.basis.orthonormalized(), w)

	# 3) el extremo conserva su orientación global (pie plano, mano estable)
	if keep_end_rotation:
		_apply_global_rot(limb.end, end_rot, w)

## Gira Head hacia la cámara, limitado respecto al cuerpo y suavizado.
func _solve_head(fwd: Vector3, right: Vector3, k: float) -> void:
	# hacia dónde mira la cámara activa -> yaw/pitch relativos al cuerpo (tune: grupo Cabeza)
	var cam := player.get_viewport().get_camera_3d()
	var look: Vector3 = -(cam.global_basis.z if cam != null else player.camera_pivot.global_basis.z)
	# yaw/pitch relativos al frente del cuerpo
	var yaw := atan2(right.dot(look), fwd.dot(look))
	var pitch := asin(clampf(look.y, -1.0, 1.0))
	# vida: cabeceo al pisar y pequeños movimientos de mirada
	var tt := _t()
	var phase := 1.0 - clampf(step_timer / maxf(step_interval, 0.1), 0.0, 1.0)
	var nod: float = -sin(TAU * phase) * deg_to_rad(tune.head_nod_deg) * body_w * tune.looseness
	var wander_p: float = (sin(tt * 0.61) * sin(tt * 1.3 + 0.7)) * deg_to_rad(tune.head_wander_pitch_deg) * tune.idle_motion
	var wander_y: float = (sin(tt * 0.43 + 2.0) * sin(tt * 0.97)) * deg_to_rad(tune.head_wander_yaw_deg) * tune.idle_motion
	pitch += nod + wander_p
	yaw += wander_y
	yaw = clampf(yaw, -deg_to_rad(tune.head_max_yaw), deg_to_rad(tune.head_max_yaw))
	pitch = clampf(pitch, -deg_to_rad(tune.head_max_pitch), deg_to_rad(tune.head_max_pitch))
	var want := fwd.rotated(Vector3.UP, -yaw)   # yaw positivo = hacia la derecha
	var pitch_axis := want.cross(Vector3.UP)
	if pitch_axis.length() > 0.001:
		want = want.rotated(pitch_axis.normalized(), pitch)
	want = want.normalized()
	if head_dir_smooth == Vector3.ZERO:
		head_dir_smooth = want
	head_dir_smooth = head_dir_smooth.lerp(want, k).normalized()

	var skel_basis := skeleton.global_basis.orthonormalized()
	var want_s := skel_basis.inverse() * head_dir_smooth
	var head_g := skeleton.get_bone_global_pose(head_idx)
	var head_rot := head_g.basis.orthonormalized()
	var cur_fwd := (head_rot * head_fwd_local).normalized()
	var q := Quaternion(cur_fwd, want_s.normalized()) if cur_fwd.dot(want_s.normalized()) > -0.999 else Quaternion.IDENTITY
	_apply_global_rot(head_idx, Basis(q) * head_rot, head_weight)
