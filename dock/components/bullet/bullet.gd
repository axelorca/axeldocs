## A single list item component.
## Supports bullet, numbered, and checkbox variants with arbitrary nesting depth.
@tool
class_name DocBullet
extends HBoxContainer


## Visual style variants for a list item.
enum TYPE {
	## A toggle checkbox item.
	CHECKBOX,
	## A numbered item.
	NUMBER,
	## An unordered bullet item.
	BULLET
}
## Nesting depth. Adds left margin proportional to the value.
@export var level: int:
	set(value):
		level = maxi(0, value)
		refresh()
		
## Visual style of the list item.
@export var type: TYPE:
	set(value):
		type = value
		refresh()

## Display number shown for [constant TYPE.NUMBER] items.
@export var bullet_number: int:
	set(value):
		bullet_number = maxi(0, value)
		refresh()


@export var bullet_margin: PanelContainer
@export var checkbox: CheckBox
@export var bullet: RichTextLabel
@export var number: RichTextLabel

@export var text_content: DocText

## Reference to the parent [DocView], resolved lazily by walking the scene tree.
var doc_view: DocView:
	get():
		if not doc_view:
			if not is_inside_tree():
				return null
			var p = get_parent()
			while p != null and not p is DocView:
				p = p.get_parent()
			doc_view = p
		return doc_view

## Guards against queuing more than one deferred refresh per frame.
var _refresh_pending: bool = false


## Updates visibility of marker nodes and applies the nesting margin, then refreshes the text.
## Deferred so that assigning several properties in a row triggers only one update.
func refresh():
	if _refresh_pending:
		return
	_refresh_pending = true
	_refresh_deferred.call_deferred()


func _refresh_deferred():
	_refresh_pending = false
	if not is_node_ready():
		await ready

	var zoom: float = doc_view.zoom if doc_view else 1.0

	bullet_margin.custom_minimum_size.x = 20 * level * zoom

	var marker_size := maxi(1, roundi(14 * zoom))
	bullet.add_theme_font_size_override("normal_font_size", marker_size)
	number.add_theme_font_size_override("normal_font_size", marker_size)
	
	bullet.visible = type == TYPE.BULLET
	checkbox.visible = type == TYPE.CHECKBOX
	number.visible = type == TYPE.NUMBER
	
	number.text = str(bullet_number, ".")
	
	await Engine.get_main_loop().process_frame
	
	text_content.refresh()


## Sets the pressed state of the checkbox marker to [param state].
func set_checkbox(state: bool):
	get_node("Bullet/CheckBox").button_pressed = state
