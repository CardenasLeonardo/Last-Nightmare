extends Area3D

## Zona de cámara fija estilo Silent Hill clásico / Little Nightmares.
## Al entrar el jugador en esta área, se activa "fixed_camera_path".
## Al salir, se restaura la cámara al hombro del jugador.

@export var fixed_camera_path: NodePath

@onready var fixed_camera: Camera3D = get_node(fixed_camera_path)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and fixed_camera:
		fixed_camera.make_current()

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		var shoulder_cam := body.get_node_or_null("CameraPivot/SpringArm3D/ShoulderCamera") as Camera3D
		if shoulder_cam:
			shoulder_cam.make_current()
