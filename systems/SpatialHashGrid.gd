class_name SpatialHashGrid
extends RefCounted
## High-performance 2D spatial hash grid for nearest-neighbor and radius queries.
## Eliminates O(N^2) distance scans on mobile CPUs.

var cell_size: float = 160.0
var _buckets: Dictionary = {}
var _item_cells: Dictionary = {}


func _init(p_cell_size: float = 160.0) -> void:
	cell_size = maxf(32.0, p_cell_size)


func clear() -> void:
	_buckets.clear()
	_item_cells.clear()


func _cell_key(pos: Vector2) -> int:
	var cx: int = int(floor(pos.x / cell_size))
	var cy: int = int(floor(pos.y / cell_size))
	return ((cx & 0xFFFF) << 16) | (cy & 0xFFFF)


func insert(item: Object, pos: Vector2) -> void:
	if item == null or not is_instance_valid(item):
		return
	var key := _cell_key(pos)
	var id := item.get_instance_id()
	_item_cells[id] = key
	if not _buckets.has(key):
		_buckets[key] = []
	(_buckets[key] as Array).append(item)


func update_item(item: Object, new_pos: Vector2) -> void:
	if item == null or not is_instance_valid(item):
		return
	var id := item.get_instance_id()
	var new_key := _cell_key(new_pos)
	if _item_cells.has(id):
		var old_key: int = _item_cells[id]
		if old_key == new_key:
			return
		if _buckets.has(old_key):
			(_buckets[old_key] as Array).erase(item)
	_item_cells[id] = new_key
	if not _buckets.has(new_key):
		_buckets[new_key] = []
	(_buckets[new_key] as Array).append(item)


func remove_item(item: Object) -> void:
	if item == null:
		return
	var id := item.get_instance_id()
	if _item_cells.has(id):
		var old_key: int = _item_cells[id]
		if _buckets.has(old_key):
			(_buckets[old_key] as Array).erase(item)
		_item_cells.erase(id)


func query_radius(center: Vector2, radius: float) -> Array:
	var results: Array = []
	var r_sq := radius * radius
	var min_cx: int = int(floor((center.x - radius) / cell_size))
	var max_cx: int = int(floor((center.x + radius) / cell_size))
	var min_cy: int = int(floor((center.y - radius) / cell_size))
	var max_cy: int = int(floor((center.y + radius) / cell_size))

	for cx in range(min_cx, max_cx + 1):
		for cy in range(min_cy, max_cy + 1):
			var key: int = ((cx & 0xFFFF) << 16) | (cy & 0xFFFF)
			if not _buckets.has(key):
				continue
			var bucket: Array = _buckets[key]
			for obj in bucket:
				if obj != null and is_instance_valid(obj) and obj is Node2D:
					var node2d := obj as Node2D
					if node2d.visible and node2d.global_position.distance_squared_to(center) <= r_sq:
						results.append(node2d)
	return results


func query_nearest(center: Vector2, max_radius: float, exclude: Object = null) -> Node2D:
	var candidates := query_radius(center, max_radius)
	var best: Node2D = null
	var best_d2 := max_radius * max_radius + 1.0
	for c in candidates:
		if c == exclude:
			continue
		var node := c as Node2D
		var d2 := node.global_position.distance_squared_to(center)
		if d2 < best_d2:
			best_d2 = d2
			best = node
	return best
