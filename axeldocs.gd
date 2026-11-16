## Axeldocs editor plugin entry point.
## Registers the documentation dock and the [code]axeldocs/docs_folder[/code]
## project setting, then cleans up when the plugin is disabled.
@tool
extends EditorPlugin

## Packed scene for the documentation dock.
const DOCK = preload("res://addons/axeldocs/dock/doc_view.tscn")
var _dock: Control
## Set when the filesystem changes while the dock is hidden; consumed on next show.
var _docs_dirty: bool = true

## Registers the project setting, instantiates the dock, and connects refresh signals.
func _enter_tree() -> void:
	# Project Settings (shows up in Project → Project Settings)
	if not ProjectSettings.has_setting("axeldocs/docs_folder"):
		ProjectSettings.set_setting("axeldocs/docs_folder", "res://docs")
	
	ProjectSettings.set_initial_value("axeldocs/docs_folder", "res://docs")
	ProjectSettings.add_property_info({
		"name": "axeldocs/docs_folder",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_DIR,
	})
	ProjectSettings.set_as_basic("axeldocs/docs_folder", true)  # show outside Advanced mode

	_dock = DOCK.instantiate()
	_dock.name = "Documentation"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	_dock.visibility_changed.connect(_on_dock_visibility_changed)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)
	if _dock.is_visible_in_tree():
		_docs_dirty = false
		_dock.refresh()


## Rebuilds immediately when the dock is on screen; otherwise defers the
## refresh until the dock becomes visible again.
func _on_filesystem_changed() -> void:
	if _dock.is_visible_in_tree():
		_docs_dirty = false
		_dock.refresh()
	else:
		_docs_dirty = true


## Refreshes only when the dock is shown and the docs changed since the last rebuild,
## so plain tab switching no longer triggers a full rebuild.
func _on_dock_visibility_changed() -> void:
	if _dock.is_visible_in_tree() and _docs_dirty:
		_docs_dirty = false
		_dock.refresh()


## Disconnects refresh signals, removes the dock from the editor, and frees it.
func _exit_tree() -> void:
	if _dock:
		EditorInterface.get_resource_filesystem().filesystem_changed.disconnect(_on_filesystem_changed)
		remove_control_from_docks(_dock)
		_dock.queue_free()
