extends SceneTree

func _init():
	var scene = load("res://scenes/Main.tscn") as PackedScene
	var inst = scene.instantiate()
	var player = inst.find_child("Player", true, false)
	get_root().add_child(inst)

	for i in range(10):
		await process_frame

	var skel: Skeleton3D = player.find_child("Skeleton3D", true, false)
	var bidx = skel.find_bone("spine_02")

	var cam = Camera3D.new()
	get_root().add_child(cam)
	cam.fov = 55
	cam.current = true

	# --- Idle (pose de reposo real, tal como queda parado sin input) ---
	var bpose: Transform3D = skel.global_transform * skel.get_bone_global_pose(bidx)
	var chest_pos: Vector3 = bpose.origin
	cam.global_position = chest_pos + Vector3(1.6, -0.1, 1.6)
	cam.look_at(chest_pos, Vector3.UP)
	for i in range(5):
		await process_frame
	get_root().get_texture().get_image().save_png("C:/Users/leona/AppData/Local/Temp/pose_idle.png")

	# --- Jump (loop de salto/caída) ---
	var anim_player: AnimationPlayer = player.find_child("AnimationPlayer", true, false)
	if anim_player.has_animation("Jump"):
		anim_player.play("Jump")
		anim_player.seek(0.2, true)
	for i in range(5):
		await process_frame
	bpose = skel.global_transform * skel.get_bone_global_pose(bidx)
	chest_pos = bpose.origin
	cam.global_position = chest_pos + Vector3(1.6, -0.1, 1.6)
	cam.look_at(chest_pos, Vector3.UP)
	for i in range(5):
		await process_frame
	get_root().get_texture().get_image().save_png("C:/Users/leona/AppData/Local/Temp/pose_jump.png")

	print("saved screenshots")
	quit()
