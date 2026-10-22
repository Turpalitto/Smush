class_name ObjectPool
extends RefCounted
## Pre-allocated Node2D object pool with hard active-instance caps to prevent GC/instantiation spikes.

var _factory: Callable
var _parent: Node
var _inactive: Array[Node2D] = []
var _active: Array[Node2D] = []
var max_active: int = 64
var reuse_hits: int = 0
var created_count: int = 0


func _init(parent_node: Node, factory_fn: Callable, p_max_active: int = 64, prewarm: int = 0) -> void:
	_parent = parent_node
	_factory = factory_fn
	max_active = maxi(1, p_max_active)
	for _i in range(mini(prewarm, max_active)):
		var inst := _create_new()
		_deactivate_node(inst)
		_inactive.append(inst)


func _create_new() -> Node2D:
	var inst: Node2D = _factory.call()
	created_count += 1
	if _parent != null and inst.get_parent() == null:
		_parent.add_child(inst)
	return inst


func _deactivate_node(node: Node2D) -> void:
	node.visible = false
	node.set_process(false)
	node.set_physics_process(false)


func acquire() -> Node2D:
	# Clean invalid references if scene changed
	for i in range(_active.size() - 1, -1, -1):
		if not is_instance_valid(_active[i]):
			_active.remove_at(i)

	if _active.size() >= max_active:
		return null

	var node: Node2D = null
	while not _inactive.is_empty():
		var cand: Node2D = _inactive.pop_back()
		if is_instance_valid(cand):
			node = cand
			reuse_hits += 1
			break

	if node == null:
		node = _create_new()

	node.visible = true
	node.set_process(true)
	node.set_physics_process(true)
	_active.append(node)
	return node


func release(node: Node2D) -> void:
	if node == null or not is_instance_valid(node):
		return
	var idx := _active.find(node)
	if idx != -1:
		_active.remove_at(idx)
	_deactivate_node(node)
	if not _inactive.has(node):
		_inactive.append(node)


func release_all() -> void:
	for i in range(_active.size() - 1, -1, -1):
		var node := _active[i]
		if is_instance_valid(node):
			_deactivate_node(node)
			if not _inactive.has(node):
				_inactive.append(node)
	_active.clear()


func active_count() -> int:
	return _active.size()


func get_active_items() -> Array[Node2D]:
	return _active
