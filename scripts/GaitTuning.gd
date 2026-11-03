class_name GaitTuning
extends Resource
## ===========================================================================
##  TODAS las constantes de la caminata en un solo sitio.
##  Se editan en el Inspector (Player -> ik_tuning) con el juego corriendo
##  (pestaña "Remoto") o aquí en el código. Todo lo demás vive en PlayerIK.gd.
##  Unidades: metros, segundos, grados (salvo que diga otra cosa).
##  "walk" = lo que mide la animación Walk de UAL (~0.6 m/s);
##  "jog"  = lo que mide Jog_Fwd (~3.4 m/s). Entre ambas se interpola por velocidad.
##  Datos: data/ual_locomotion_joints.csv + Teoría/Datos de locomoción UAL.
## ===========================================================================

# ---------------------------------------------------------------------------
# >>> Se usa en PlayerIK.gd: _phase_legs / _phase_arms / _phase_head / _phase_limits (interruptores)
@export_group("Activar / desactivar partes")
@export_flags_3d_physics var collision_mask: int = 1   ## capas que cuentan como piso/pared para los rayos
@export var feet: bool = true               ## pies se apoyan en el piso (escalones, rampas)
@export var procedural_walk: bool = true    ## pasos propios al caminar/quieto (no usa el ciclo de piernas grabado)
@export var hands: bool = true              ## manos se apoyan en la pared si estás quieto frente a ella
@export var head: bool = true               ## la cabeza mira hacia donde apunta la cámara
@export var joint_limits: bool = true       ## límites articulares (rodillas/codos no se doblan al revés)

# ---------------------------------------------------------------------------
# >>> Se usa en PlayerIK.gd: casi todas las funciones de movimiento (_pelvis_twist, _torso_motion, _swing_arms, _solve_head)
@export_group("Globales (todo se escala con esto)")
@export_range(0.0, 1.6) var looseness: float = 1.0       ## holgura: balanceo de cadera/torso/brazos al caminar
@export_range(0.0, 2.0) var idle_motion: float = 1.0     ## vida en reposo: respiración, cambio de peso, mirada
@export_range(0.0, 2.0) var torso_dynamics: float = 1.0  ## el torso se retrasa/inclina con aceleración y curvas
@export var limit_scale: float = 1.0                     ## >1 ensancha los límites articulares

# >>> Se usa en PlayerIK.gd: _gt() y los factores de velocidad (sf) de cadera, torso y brazos
@export_group("Velocidades de referencia")
@export var ref_walk_speed: float = 0.6     ## velocidad de la animación Walk de UAL
@export var ref_jog_speed: float = 20     ## velocidad de Jog_Fwd de UAL
@export var motion_speed_ref: float = 0.9   ## por debajo de esta velocidad la cadera/torso se mueven proporcionalmente menos
@export var arm_speed_ref: float = 1.5      ## el vaivén de brazos llega al máximo a esta velocidad (x1.3 de tope)
@export var body_blend_speed: float = 1.3   ## a esta velocidad el "cuerpo completo" está al 100 %

# ---------------------------------------------------------------------------
# >>> Se usa en PlayerIK.gd: _step_legs() — cuándo y dónde aterriza cada paso
@export_group("Cadencia y zancada")
@export var stride_fraction: float = 2        ## medio paso respecto al largo de la pierna (a 2 m/s)
@export var stride_speed_slope: float = 0.2     ## cuánto crece el medio paso por m/s de velocidad
@export var stride_min: float = 0.1             ## medio paso mínimo (x largo de pierna)
@export var stride_max: float = 0.62            ## medio paso máximo (x largo de pierna)
@export var cadence_k: float = 0.26             ## UAL: velocidad = k * pasos_por_s^2 (para pierna de 0.55 m)
@export var ref_leg_length: float = 0.4        ## largo de pierna al que están medidos cadence_k y max_step_length
@export var max_step_length: float = 0.3       ## paso más largo que alcanza la pierna apoyando (para 0.55 m)
@export var step_interval_min: float = 0.3      ## tiempo mínimo entre pasos
@export var step_interval_max: float = 0.9      ## tiempo máximo entre pasos
@export var step_interval_jitter: float = 0.04  ## variación aleatoria del tiempo entre pasos (±fracción)
@export var swing_fraction: float = 0.8         ## duración del pie en el aire / intervalo entre pasos
@export var swing_min: float = 0.12             ## segundos mínimos de un paso en el aire
@export var swing_max: float = 0.45             ## segundos máximos de un paso en el aire
@export var landing_ahead_min: float = 0.4      ## el pie aterriza como mínimo a esto x medio paso por delante
@export var landing_ahead_max: float = 1.3      ## ... y como máximo a esto
@export var leg_reach_factor: float = 1.012     ## aterriza con la pierna estirada (1.0 = justo el largo)
@export var landing_hover: float = 0.6          ## cuánto de la tolerancia puede quedar el pie sin tocar al aterrizar
@export var emergency_step_ratio: float = 0.8   ## si un pie se aleja tanto (x largo pierna) de su cadera, paso de emergencia
@export var landing_follow_rate: float = 18.0   ## suavizado del punto de aterrizaje (evita tirones al soltar la tecla)
@export var gait_phase_rate: float = 18.0       ## suavizado de la fase de marcha (usada por brazos y torso)
@export var step_mul_min: float = 0.9           ## variación del largo de cada paso (nunca se alarga, solo se acorta)
@export var step_mul_max: float = 1.0
@export var lift_mul_min: float = 0.85          ## variación de la altura de cada paso
@export var lift_mul_max: float = 1.15
@export var landing_side_jitter: float = 0.015  ## desvío lateral aleatorio de cada aterrizaje (±m)
@export var step_yaw_jitter_deg: float = 3.0    ## giro aleatorio de la punta en cada paso (±°)

# ---------------------------------------------------------------------------
# >>> Se usa en PlayerIK.gd: _phase_legs() (tolerancia al alcance, piso) y _step_legs() (zona de comodidad)
@export_group("Umbrales (imperfección permitida)")
@export var foot_tolerance: float = 0.05        ## m que el pie puede quedar corto/flotando sin bajar la cadera
@export var ground_deadband: float = 0.02       ## desniveles menores a esto se ignoran
@export var foot_max_offset: float = 0.25       ## cuánto puede subir/bajar un pie respecto al cuerpo (escalones)
@export var comfort_trigger: float = 0.015     ## quieto: el pie se recoloca solo si se sale tanto (m) de su zona de comodidad
@export var stop_stagger_ref: float = 0.5       ## al parar: diferencia de pies (m) que cuenta como "intercalados" al 100 %
@export var stop_speed_ref: float = 3.0         ## al parar: velocidad (m/s) que cuenta como "iba rápido" al 100 %
@export var stop_uneven_ref: float = 0.08       ## al parar: desnivel entre pies (m) que cuenta como "piso desigual" al 100 %

# ---------------------------------------------------------------------------
# >>> Se usa en PlayerIK.gd: _foot_pitch(), _proc_foot_target() y la rotación del pie en _phase_legs()
@export_group("Pie: altura y pisada")
@export var step_height: float = 0.07           ## altura del pie al dar un paso
@export var step_height_speed_base: float = 0.1 ## la altura crece con la velocidad: base + velocidad * pendiente
@export var step_height_speed_slope: float = 0.1
@export var step_height_speed_max: float = 1.2
@export var toe_out_deg: float = 6.0            ## apertura natural de las puntas
@export var heel_strike_deg: float = 20.0       ## punta arriba al pisar con el talón
@export var toe_off_deg: float = -70.0          ## punta abajo al despegar
@export var swing_flat_deg: float = -15.0        ## inclinación del pie a media zancada en el aire
@export var swing_toe_off_end: float = 0.7      ## fracción del aire en que termina el despegue
@export var swing_heel_end: float = 0.55        ## fracción del aire (desde swing_toe_off_end, ancho) en que ya es talón
@export var stance_estimate: float = 2       ## duración estimada del apoyo / intervalo (para la pisada)
@export var stance_heel_end: float = 0.28       ## fracción del apoyo en que el pie ya está plano
@export var stance_flat_end: float = 0.62       ## fracción del apoyo en que empieza a subir el talón
@export var ankle_roll: float = 2.5             ## cuánto sube el tobillo al despegar de punta (x altura de tobillo)
@export var foot_pitch_rate: float = 40.0       ## suavizado de la inclinación del pie
@export var foot_yaw_rate: float = 20          ## suavizado del giro de la punta

# ---------------------------------------------------------------------------
# >>> Se usa en PlayerIK.gd: _phase_legs() ([3] rebote y balanceo), _pelvis_twist(), _drop_pelvis()
@export_group("Cadera")
@export var pelvis_roll_walk_deg: float = 7   ## balanceo lateral de la cadera (UAL walk)
@export var pelvis_roll_jog_deg: float = 7    ## (UAL jog)
@export var pelvis_twist_deg: float = 1       ## giro de la cadera con cada paso
@export var pelvis_bob: float = 0.07            ## rebote vertical (m): baja al pisar, sube a mitad del paso
@export var pelvis_sway: float = 0.07           ## desplazamiento lateral hacia el pie de apoyo (m)
@export var pelvis_drop_max: float = 0.2        ## lo máximo que baja la cadera para que llegue una pierna
@export var pelvis_drop_rate: float = 40.0      ## suavizado de la bajada de cadera
@export var sway_rate: float = 20.0             ## suavizado del desplazamiento lateral
@export var swing_q_rate: float =20.0          ## suavizado de "qué pierna está en el aire"
@export var body_blend_rate: float = 3.0        ## con qué rapidez entra/sale el movimiento de cuerpo completo

# ---------------------------------------------------------------------------
# >>> Se usa en PlayerIK.gd: _torso_motion() — resorte del torso, curvas, aceleración, hombros
@export_group("Torso y hombros")
@export var spine_yaw_walk_deg: float = 6     ## giro de la columna alta (UAL walk)
@export var spine_yaw_jog_deg: float = 50.0     ## (UAL jog)
@export var spine_yaw_factor: float = 0.5       ## cuánto de ese giro pasa al objetivo del resorte
@export var spine_roll_walk_deg: float = 3    ## ladeo de la columna al ritmo del paso
@export var spine_roll_jog_deg: float = 4.0
@export var body_lean_deg: float = 7.0          ## inclinación hacia adelante al caminar
@export var accel_lean_deg: float = 5         ## ° de inclinación por cada m/s² de aceleración
@export var accel_limit: float = 4.0            ## aceleración máxima considerada (m/s²)
@export var turn_lean_deg: float = 5.0          ## ladeo hacia adentro en curvas (° por rad/s * m/s)
@export var turn_lag: float = 0.4              ## los hombros se quedan atrás al girar (rad por rad/s)
@export var turn_rate_limit: float = 2.5        ## tasa de giro máxima considerada (rad/s)
@export var turn_filter_rate: float = 6.0       ## filtrado de la tasa de giro
@export var torso_roll_limit_deg: float = 8.0   ## tope del ladeo del torso
@export var torso_yaw_limit_deg: float = 14.0   ## tope del giro del torso
@export var torso_spring_w: float = 7.5         ## rigidez del resorte del torso (rad/s): mayor = más rápido
@export var torso_spring_z: float = 0.2        ## amortiguación del resorte (0 = rebota sin fin, 1 = sin rebote)
@export var shoulder_roll_deg: float = 6      ## los hombros suben/bajan al ritmo del paso
@export var shoulder_yaw_deg: float = 2.5       ## y giran un poco

# ---------------------------------------------------------------------------
# >>> Se usa en PlayerIK.gd: _swing_arms() (péndulo) y _phase_arms() (manos en pared)
@export_group("Brazos")
@export var arm_swing_deg: float = 30.0         ## balanceo de los brazos
@export var arm_spring_w: float = 7.0           ## frecuencia natural del péndulo del brazo (rad/s)
@export var arm_spring_z: float = 0.42          ## amortiguación del brazo
@export var elbow_spring_w: float = 11.0
@export var elbow_spring_z: float = 0.6
@export var elbow_walk_deg: float = 10.0        ## flexión del codo caminando
@export var elbow_jog_deg: float = 80.0         ## ... y trotando
@export var elbow_swing_deg: float = 8.0        ## cuánto más se dobla al ir adelante
@export var arm_out: float = 0.12               ## separación de los brazos del cuerpo (x holgura)
@export var arm_blend_rate: float = 3.0         ## con qué rapidez entra/sale el vaivén
@export var hand_reach_distance: float = 0.6    ## distancia máx. a la pared para apoyar las manos
@export var hand_idle_speed: float = 0.6        ## solo apoya manos si va más lento que esto

# ---------------------------------------------------------------------------
# >>> Se usa en PlayerIK.gd: _solve_head()
@export_group("Cabeza")
@export_range(0.0, 1.0) var head_weight: float = 0.8
@export var head_max_yaw: float = 70.0          ## grados, respecto al cuerpo
@export var head_max_pitch: float = 35.0
@export var head_nod_deg: float = 1.5           ## cabeceo al ritmo del paso
@export var head_wander_pitch_deg: float = 4.0  ## movimientos lentos de mirada (reposo)
@export var head_wander_yaw_deg: float = 9.0

# ---------------------------------------------------------------------------
# >>> Se usa en PlayerIK.gd: _pelvis_twist() y _torso_motion() cuando el personaje está quieto
@export_group("Reposo (vida)")
@export var idle_shift_deg: float = 3.5         ## cambio de peso: ladeo de cadera
@export var idle_yaw_deg: float = 4.0           ## giro lento de cadera
@export var breath_deg: float = 1.8             ## respiración (torso)
@export var idle_counter_deg: float = 2.6       ## el torso compensa el cambio de peso
@export var idle_blend_rate: float = 4.0

# ---------------------------------------------------------------------------
# >>> Se usa en PlayerIK.gd: _phase_limits()
@export_group("Límites articulares")
@export var knee_walk_max_deg: float = 105.0    ## flexión máxima de rodilla caminando (la máx. libre es la de abajo)
@export var gimbal_guard_deg: float = 80.0      ## cerca del gimbal lock los límites de Euler no se aplican
## Bisagras: hueso -> Vector2(mínimo, máximo) de flexión en grados.
@export var hinge_limits: Dictionary = {
	"calf_l": Vector2(-3.0, 140.0), "calf_r": Vector2(-3.0, 140.0),
	"lowerarm_l": Vector2(-3.0, 150.0), "lowerarm_r": Vector2(-3.0, 150.0),
}
## Rótulas: hueso -> [x_min, x_max, y_max, z_max] en grados (Euler YXZ respecto al reposo).
@export var ball_limits: Dictionary = {
	"spine_02": [-25.0, 55.0, 25.0, 25.0], "spine_03": [-20.0, 45.0, 45.0, 25.0],
	"neck_01": [-45.0, 40.0, 55.0, 25.0], "Head": [-45.0, 50.0, 50.0, 30.0],
	"clavicle_l": [-30.0, 25.0, 15.0, 50.0], "clavicle_r": [-30.0, 25.0, 15.0, 50.0],
	"thigh_l": [-110.0, 45.0, 50.0, 50.0], "thigh_r": [-110.0, 45.0, 50.0, 50.0],
	"foot_l": [-55.0, 55.0, 40.0, 45.0], "foot_r": [-55.0, 55.0, 40.0, 45.0],
}
