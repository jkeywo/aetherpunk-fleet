extends RefCounted
## Draw compact difficulty marks without depending on a platform's glyph coverage.

static var ratings: Dictionary = {}

static func texture(rating: int) -> Texture2D:
	if ratings.has(rating): return ratings[rating]
	var large := floori(rating / 5.0)
	var small := rating % 5
	var image := Image.create(large * 34 + small * 23, 32, false, Image.FORMAT_RGBA8)
	var x := 0
	for i in large:
		_skull(image, x, 0, 31, 32, true)
		x += 34
	for i in small:
		_skull(image, x, 6, 20, 24, false)
		x += 23
	var result := ImageTexture.create_from_image(image)
	ratings[rating] = result
	return result

static func _skull(image: Image, left: int, top: int, width: int, height: int, marked: bool) -> void:
	var bone := Color("#f0ca8e") if marked else Color("#dcc9a6")
	var hollow := Color("#35292a")
	for y in height:
		for x in width:
			var u := float(x) / (width - 1)
			var v := float(y) / (height - 1)
			var crown := Vector2((u - 0.5) / 0.47, (v - 0.42) / 0.41).length_squared()
			var jaw := u >= 0.28 and u <= 0.72 and v >= 0.64 and v <= 0.92
			if crown > 1.0 and not jaw: continue
			var eye := Vector2((absf(u - 0.5) - 0.21) / 0.125, (v - 0.55) / 0.10).length_squared()
			var nose := absf(u - 0.5) < 0.05 and v >= 0.65 and v <= 0.72
			var tooth := v > 0.79 and (absi(x - width / 2) <= 0 or absi(x - width / 2) == roundi(width * 0.12))
			var color := bone.darkened(0.17) if crown > 0.89 and not jaw else bone
			image.set_pixel(left + x, top + y, hollow if eye < 1.0 or nose or tooth else color)
	if marked:
		var number := ["111", "100", "111", "001", "111"]
		for row in number.size():
			for column in 3:
				if number[row][column] == "1":
					image.fill_rect(Rect2i(left + 12 + column * 2, top + 3 + row * 2, 2, 2), hollow)
