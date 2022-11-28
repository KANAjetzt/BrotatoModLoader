extends Node

const MOD_PRIORITY = 2

func KANA_edit_explosion_animation(animation_player):
	ModLoader.mod_log("KANAExplosionMute: start editing explosion animation.")
	# load new explosion texture
	var explosion_texture = StreamTexture.new()
	explosion_texture.load("res://KANAExplosionMute/KANA_explosion.png-c9c3e26ba4d78f15a3f036bd213acaa6.stex")
	# get explode animation
	var animation_explode = animation_player.get_animation('explode')
	# get the sprite texture track index
	var track_sprite_index = animation_explode.find_track('Sprite:texture')
	# remove it
	animation_explode.remove_track(track_sprite_index)
	# create a new track with the new explosion texture
	var new_track_index = animation_explode.add_track(Animation.TYPE_VALUE)
	animation_explode.track_set_path(new_track_index, "Sprite:texture")
	animation_explode.track_insert_key(new_track_index, 0.0, explosion_texture)
	animation_explode.track_insert_key(new_track_index, 0.05, '')
	ModLoader.mod_log("KANAExplosionMute: finished editing explosion animation.")

func _init(modLoader = ModLoader):
	modLoader.mod_log("KANAExplosionMute: initing")
#	modLoader.installScriptExtension("res://KANAExplosionMute/projectiles/player_explosion.gd")

func _ready():
	ModLoader.mod_log("KANAExplosionMute: finished")
	
	var scene_explosion = preload("res://projectiles/explosion.tscn").instance()
	var animation_player = scene_explosion.get_node("AnimationPlayer")
	KANA_edit_explosion_animation(animation_player)
	
	ModLoader.saveScene(scene_explosion, "res://projectiles/explosion.tscn")
