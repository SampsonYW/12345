# bgm_manager.gd
# BGM 管理：监听 GameManager 状态和位置变化，切换 AudioStreamPlayer 的曲目。
# 挂在 Game3D 节点下，启动时由 game_3d.gd 添加。
# [AI-ASSISTED] 2026-05-26 — 美术资源接入：BGM 按位置/状态切换
extends Node

const BGM_TITLE := preload("res://assets/audio/bgm/bgm_title.mp3")
const BGM_AFTERGLOW := preload("res://assets/audio/bgm/bgm_afterglow.mp3")
const BGM_EXPLORATION := preload("res://assets/audio/bgm/bgm_exploration.mp3")
const BGM_EXTRACTION := preload("res://assets/audio/bgm/bgm_extraction.mp3")
const BGM_EXTRACTION_END := preload("res://assets/audio/bgm/bgm_extraction_end.mp3")
const BGM_SUCCESS := preload("res://assets/audio/bgm/bgm_success.mp3")
const BGM_DEATH := preload("res://assets/audio/bgm/bgm_death.mp3")

const FADE_DURATION := 1.2
const DEFAULT_VOLUME_DB := -8.0

var _player: AudioStreamPlayer = null
var _current_track: AudioStream = null
var _tween: Tween = null


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "BGMPlayer"
	_player.bus = "Master"
	_player.volume_db = DEFAULT_VOLUME_DB
	_player.autoplay = false
	add_child(_player)
	if not GameManager.state_changed.is_connected(_on_state_changed):
		GameManager.state_changed.connect(_on_state_changed)
	if not GameManager.location_changed.is_connected(_on_location_changed):
		GameManager.location_changed.connect(_on_location_changed)
	_update_track()


func _on_state_changed(_new_state: int) -> void:
	_update_track()


func _on_location_changed(_new_location: int) -> void:
	_update_track()


func _update_track() -> void:
	var track: AudioStream = _pick_track()
	if track == _current_track:
		return
	_current_track = track
	_play_with_fade(track)


func _pick_track() -> AudioStream:
	# DEAD / SUCCESS 优先于 location
	match GameManager.current_state:
		GameManager.State.DEAD:
			return BGM_DEATH
		GameManager.State.SUCCESS:
			return BGM_SUCCESS
		GameManager.State.EXTRACTING:
			return BGM_EXTRACTION
	# 按位置选 BGM
	match GameManager.current_location:
		GameManager.Location.TITLE:
			return BGM_TITLE
		GameManager.Location.AFTERGLOW:
			return BGM_AFTERGLOW
		GameManager.Location.EXPEDITION:
			return BGM_EXPLORATION
	return BGM_TITLE


func _play_with_fade(stream: AudioStream) -> void:
	if _player == null:
		return
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", -40.0, FADE_DURATION * 0.4)
	_tween.tween_callback(_swap_stream.bind(stream))
	_tween.tween_property(_player, "volume_db", DEFAULT_VOLUME_DB, FADE_DURATION * 0.6)


func _swap_stream(stream: AudioStream) -> void:
	if _player == null:
		return
	_player.stop()
	_player.stream = stream
	if stream != null:
		_player.play()
