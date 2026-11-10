extends RefCounted
## Declarative visual rigs: shared validation, sprite discovery and import.
const BASE := "res://assets/generated/rigs/"
static var texture_cache: Dictionary = {}

static func empty(id: String = "visual") -> Dictionary:
	return {"id": id, "canvas": [1000,650], "parts": [], "cables": []}

static func texture_path(rig: Dictionary, part: Dictionary, base: String = BASE) -> String:
	var source: Variant = part.get("texture",rig.get("atlas",""))
	if not source is String: return ""
	return source if source.begins_with("res://") else base.path_join(source)

static func valid_path(path: String) -> bool:
	return path.begins_with("res://assets/") and not path.contains("..") and path.get_extension().to_lower()=="png"

static func load_texture(path: String) -> Texture2D:
	if not valid_path(path) or not (FileAccess.file_exists(path) or ResourceLoader.exists(path)): return null
	if not texture_cache.has(path):
		if FileAccess.file_exists(path+".import") and ResourceLoader.exists(path):
			texture_cache[path]=load(path) as Texture2D
		else:
			var image := Image.load_from_file(path)
			if image == null or image.is_empty(): return null
			texture_cache[path]=ImageTexture.create_from_image(image)
	return texture_cache[path]

static func vector(value: Variant, count: int, minimum: float = -100000, maximum: float = 100000) -> bool:
	if not value is Array or value.size()!=count: return false
	for item in value:
		if not (item is int or item is float) or not is_finite(float(item)) or item<minimum or item>maximum: return false
	return true

static func number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=minimum and value<=maximum

static func validate(value: Variant, where: String = "Visual rig", single_root: bool = true) -> Array:
	var errors: Array = []
	if not value is Dictionary: return [where+": expected a rig object."]
	if not value.get("id") is String or str(value.get("id","")).is_empty(): errors.append(where+": choose a nonempty rig ID.")
	if not value.get("parts") is Array: return [where+": parts must be a list."]
	if value.parts.size()>64: return [where+": use at most 64 sprite parts."]
	if not vector(value.get("canvas",[1000,650]),2,1): errors.append(where+": canvas dimensions must be positive.")
	var ids: Dictionary={}
	var roots:=0
	for index in value.parts.size():
		var part: Variant=value.parts[index]
		var label:=where+" part "+str(index+1)
		if not part is Dictionary: errors.append(label+": expected an object."); continue
		var id: Variant=part.get("id")
		if not id is String or str(id).strip_edges().is_empty() or ids.has(id): errors.append(label+": choose a unique nonempty part ID.")
		else: ids[id]=part
		if not vector(part.get("size"),2,.01): errors.append(label+": width and height must be positive.")
		if not vector(part.get("pivot"),2,0,1): errors.append(label+": local pivot must be between 0 and 1.")
		if part.get("parent","")=="":
			roots+=1
			if not vector(part.get("position"),2): errors.append(label+": root needs an X/Y position.")
		else:
			if not part.parent is String: errors.append(label+": parent must be a part ID.")
			if not vector(part.get("anchor"),2,0,1): errors.append(label+": parent attachment must be between 0 and 1.")
		if not vector(part.get("offset",[0,0]),2): errors.append(label+": offset needs finite X/Y values.")
		if not number(part.get("z",0),-1000,1000): errors.append(label+": layer must be between -1000 and 1000.")
		if not number(part.get("rest_degrees",0),-360,360): errors.append(label+": rest rotation must be between -360 and 360 degrees.")
		for flag in ["flip_x","flip_y"]:
			if not part.get(flag,false) is bool: errors.append(label+": "+flag+" must be enabled or disabled.")
		if not number(part.get("opacity",1),0,1): errors.append(label+": opacity must be between 0 and 1.")
		var motion: Variant=part.get("motion")
		if not motion is Dictionary: errors.append(label+": configure idle motion.")
		else:
			if not number(motion.get("degrees"),0,180): errors.append(label+": oscillation must be between 0 and 180 degrees.")
			if not number(motion.get("period"),.05,3600): errors.append(label+": cycle must last at least 0.05 seconds.")
			if not number(motion.get("phase"),-100000,100000): errors.append(label+": phase must be finite.")
			if not number(motion.get("bob_y"),0,1000): errors.append(label+": vertical drift must be between 0 and 1000.")
			if not motion.get("enabled",true) is bool: errors.append(label+": idle motion must be enabled or disabled.")
		var path:=texture_path(value,part)
		var image: Texture2D=load_texture(path)
		if image==null: errors.append(label+": choose an existing PNG under res://assets/ (missing "+path+").")
		var region: Variant=part.get("region")
		if not vector(region,4,0) or (region is Array and region.size()==4 and (region[2]<=0 or region[3]<=0)):
			errors.append(label+": sprite region needs X, Y, positive width and positive height.")
		elif image!=null and (region[0]+region[2]>image.get_width()+.01 or region[1]+region[3]>image.get_height()+.01):
			errors.append(label+": sprite region is outside the selected image.")
	if not value.parts.is_empty() and single_root and roots!=1: errors.append(where+": link all parts to exactly one root body (currently %d roots)."%roots)
	for id in ids:
		var part: Dictionary=ids[id]
		var parent: Variant=part.get("parent","")
		if parent!="" and not ids.has(parent): errors.append(where+" / "+id+": parent '"+str(parent)+"' does not exist.")
		var visited: Array=[id]
		while parent is String and parent!="" and ids.has(parent):
			if visited.has(parent): errors.append(where+" / "+id+": parent links form a cycle."); break
			visited.append(parent); parent=ids[parent].get("parent","")
	var cables: Variant=value.get("cables",[])
	if not cables is Array: errors.append(where+": cables must be a list.")
	else:
		for cable in cables:
			if not cable is Dictionary: errors.append(where+": cable needs two endpoints."); continue
			for side in ["from","to"]:
				if not ids.has(cable.get(side,"")): errors.append(where+": cable "+side+" part does not exist.")
				if not vector(cable.get(side+"_uv"),2,0,1): errors.append(where+": cable "+side+" socket must be between 0 and 1.")
	return errors

static func ordered_parts(value: Dictionary) -> Array:
	var remaining: Array=value.get("parts",[]).duplicate()
	var result: Array=[]
	var seen: Dictionary={}
	while not remaining.is_empty():
		var progress:=false
		for part in remaining.duplicate():
			if part.get("parent","")=="" or seen.has(part.parent):
				result.append(part);seen[part.id]=true;remaining.erase(part);progress=true
		if not progress: return []
	return result

static func editable(value: Dictionary, id: String = "visual") -> Dictionary:
	if value.is_empty(): return empty(id)
	var result:=value.duplicate(true)
	result["id"]=id
	result["canvas"]=result.get("canvas",[1000,650])
	result["cables"]=result.get("cables",[])
	for part in result.parts:
		part["z"]=part.get("z",0)
		if part.get("parent","")=="":part.erase("parent")
		part["texture"]=texture_path(result,part)
		part.erase("pivot_px")
	return result

static func templates() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string(BASE+"rigs.json")).rigs

static func _pngs(directory: String, result: Array) -> void:
	var dir:=DirAccess.open(directory)
	if dir==null:return
	for name in dir.get_files():
		if name.get_extension().to_lower()=="png":result.append(directory.path_join(name))
	for name in dir.get_directories(): _pngs(directory.path_join(name),result)

static func sprites() -> Array:
	var result: Array=[]
	for rig in templates():
		for part in rig.parts:
			result.append({"label":rig.name+" / "+str(part.id).replace("_"," "),"texture":texture_path(rig,part),"region":part.region.duplicate(),"pivot":part.pivot.duplicate()})
	var paths: Array=[]
	_pngs("res://assets",paths)
	paths.sort()
	for path in paths:
		var image:=load_texture(path)
		if image!=null:result.append({"label":"Full image / "+path.trim_prefix("res://assets/"),"texture":path,"region":[0,0,image.get_width(),image.get_height()],"pivot":[.5,.5]})
	return result

static func import_png(path: String, directory: String = "res://assets/imported/rigs") -> Dictionary:
	if not (directory.begins_with("res://assets/") or directory.begins_with("user://")) or directory.contains(".."):
		return {"ok":false,"error":"Choose a project asset directory."}
	var bytes:=FileAccess.get_file_as_bytes(path)
	if bytes.is_empty() or bytes.size()>32*1024*1024:return {"ok":false,"error":"Choose a readable PNG smaller than 32 MB."}
	var image:=Image.new()
	if image.load_png_from_buffer(bytes)!=OK or image.get_width()>8192 or image.get_height()>8192:
		return {"ok":false,"error":"Choose a valid PNG no larger than 8192 × 8192."}
	var hash:=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
	var name:=path.get_file().get_basename().validate_filename().replace(" ","_").to_lower()
	var destination:=directory.path_join(name+"_"+hash.finish().hex_encode().substr(0,12)+".png")
	if not FileAccess.file_exists(destination):
		var error:=DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		if error!=OK:return {"ok":false,"error":"Cannot create asset directory: "+error_string(error)}
		var file:=FileAccess.open(destination+".tmp",FileAccess.WRITE)
		if file==null:return {"ok":false,"error":"Cannot write imported image: "+error_string(FileAccess.get_open_error())}
		file.store_buffer(bytes);file.flush();error=file.get_error();file.close()
		if error==OK:error=DirAccess.rename_absolute(ProjectSettings.globalize_path(destination+".tmp"),ProjectSettings.globalize_path(destination))
		if error!=OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(destination+".tmp"))
			return {"ok":false,"error":"Cannot import image: "+error_string(error)}
	return {"ok":true,"path":destination,"region":[0,0,image.get_width(),image.get_height()]}
