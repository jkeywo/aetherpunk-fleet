extends RefCounted
## One vocabulary and icon set for cards, combat, preparation, and authoring.
static var textures: Dictionary = {}
static var matcher: RegEx
const POSITION_GLYPHS := {
	"front": preload("res://assets/generated/reactions/front.png"),
	"upper": preload("res://assets/generated/reactions/upper.png"),
	"lower": preload("res://assets/generated/reactions/lower.png"),
	"rear": preload("res://assets/generated/reactions/rear.png"),
}
const DEFINITIONS := {
	"melee": ["Melee", "#ffaf88", "Attack presentation: the attacker swoops to the target, strikes, and returns. Range and target pattern remain defined separately.", "M3 4l12 12M6 2l16 16-4 4L2 6zM3 21l6-6M2 17l5 5"],
	"ranged": ["Ranged", "#8ceaff", "Attack presentation: a projectile launches from the unit's named attack marker. Short/Long range is a separate gameplay rule.", "M2 12h18M15 7l6 5-6 5M3 6h6M3 18h6"],
	"beam": ["Beam", "#8ceaff", "A piercing line: from Front or Rear hits enemy Front and Rear; from a flank hits the matching flank. Short range still excludes Rear.", "M2 8h20M2 12h20M2 16h20M8 5v14M17 5v14"],
	"explosion": ["Explosion", "#ffac79", "Separate ordered effects on the main target and each occupied adjacent position. Targets are locked before the blast; empty slots are skipped.", "M12 2l2 6 6-4-3 7 5 2-7 2 3 7-6-4-5 4 2-7-7-2 6-2-3-7 7 4z"],
	"cost": ["Cost", "#f0d49b", "Mana cost: pay with other hand cards and temporary mana crystals. Excess payment is lost.", "M12 3a9 9 0 110 18 9 9 0 010-18M10 8h3v9M9 17h7"],
	"attack": ["Attack", "#ec756b", "Attack card / deal damage. Each hit resolves cover, armour, shields, then hull.", "M5 19L19 5M12 5h7v7M5 12v7h7"],
	"guard": ["Guard", "#76b8fa", "Guard card: a defensive card type.", "M12 3L20 6v6c0 5-8 9-8 9S4 17 4 12V6z"],
	"manoeuvre": ["Manoeuvre", "#5ed4dd", "Manoeuvre card / move or swap along formation links. Basic moves discard a ship's card.", "M4 8h14l-4-4M20 16H6l4 4M18 8l-4 4M6 16l4-4"],
	"support": ["Support", "#86d6a1", "Support card: repair, coordination, and utility.", "M9 3h6v6h6v6h-6v6H9v-6H3V9h6z"],
	"mana": ["Mana", "#c789f3", "Temporary mana crystal. One crystal pays one mana; unspent crystals expire at fleet-phase end. Purple crystals on a card show its discard production.", "M12 2l7 10-7 10-7-10zM5 12h14M12 2v20"],
	"hull": ["Hull", "#f59489", "Hull / HP. A ship at zero is disabled and can be repaired.", "M3 9h18l-4 10H7zM7 9V4h10v5"],
	"damage": ["Damage", "#f38071", "Damage per hit: cover first, then armour, then shields, then hull. Armour applies separately to every hit.", "M14 2L4 14h7l-1 8 10-13h-7z"],
	"armour": ["Armour", "#c6cbd6", "Armour reduces each hit after cover. It is not consumed and protects shields and hull.", "M7 3l5 3 5-3 4 6-4 3v9H7v-9L3 9z"],
	"shields": ["Shields", "#7cbfff", "Shields are temporary HP carried by a ship. They absorb damage after armour and expire at next player-turn start.", "M12 3L20 6v6c0 5-8 9-8 9S4 17 4 12V6zM8 12h8M12 8v8"],
	"cover": ["Cover", "#ddb77e", "Cover is temporary HP belonging to a formation slot. It absorbs damage before armour and stays when ships move.", "M3 19V8l9-5 9 5v11M7 19v-7h10v7M2 21h20"],
	"repair": ["Repair", "#8ce2a3", "Repair restores hull, including on disabled ships.", "M5 19L17 7M14 3a6 6 0 007 7l-5 6-4-4-7 9-3-3 9-7-4-4z"],
	"revive": ["Revive", "#a2efc5", "A disabled ship rejoins once repaired to at least 6 hull.", "M5 12a7 7 0 111 5M5 12V5M5 12h7M12 7v10M8 12h8"],
	"weapon": ["Weapon", "#f0bc78", "Weapon damage and range come from the acting ship, including its active upgrades.", "M3 9h13v6H3zM16 10h6v4h-6M6 15v5h6v-5"],
	"short": ["Short", "#f0a079", "Short range: cannot attack from or target Rear, or cross between opposite flanks.", "M5 12h14M14 7l5 5-5 5M5 7v10"],
	"long": ["Long", "#b0cfff", "Long range: may attack from or target any occupied position.", "M2 12h20M17 7l5 5-5 5M2 7v10M7 7v10"],
	"draw": ["Draw", "#8acfe6", "Draw from the shared deck; reshuffle the discard pile when needed.", "M4 3h11v14H4zM8 7h11v14H8M14 10v7M11 14l3 3 3-3"],
	"discard": ["Discard", "#c69adb", "Deliberate discards can trigger abilities. Automatic circle cleanup cannot. Payment discards commit after the played card and allied chains.", "M5 3h10v12H5zM16 10v11M12 17l4 4 4-4"],
	"deck": ["Deck", "#a8c4d6", "Shared fleet draw pile. Order is hidden; an empty pile reshuffles discards.", "M4 4h13v13H4zM7 7h13v13H7M10 10h13v13H10"],
	"scry": ["Scry", "#d3a4f5", "Reveal up to X deck cards. Discard any of them, shuffle the rest, and return them to the top.", "M2 12s4-7 10-7 10 7 10 7-4 7-10 7-10-7-10-7zM15 12a3 3 0 11-6 0 3 3 0 016 0"],
	"stun": ["Stun", "#f4da84", "Suppress one chosen visible reaction for the rest of this fleet phase. Enemy-phase activity still happens.", "M12 2l3 6 7 1-5 5 1 8-6-4-6 4 1-8-5-5 7-1z"],
	"confuse": ["Confuse", "#de9ce9", "Discard one visible stance card and reveal its replacement. A replacement cannot react to the action that revealed it.", "M4 7h13l-4-4M20 17H7l4 4M17 7l-4 4M7 17l4-4M10 6l4 12"],
	"persistence": ["Persistence", "#d1a1f6", "At turn cleanup, remove one token and retain the card, even when it reaches zero. A card starting cleanup at zero is discarded.", "M12 3a9 9 0 110 18 9 9 0 010-18M12 6v6l5 3"],
	"resource": ["Resource", "#e4bf76", "Personal ship resource: persists between rounds, resets on defeat, and is gained or spent by authored rules.", "M12 2l9 5v10l-9 5-9-5V7zM3 7l9 5 9-5M12 12v10"],
	"adjacent": ["Adjacent", "#c2a1f3", "Connected by a formation or magic-circle edge. Initially circle cards have two neighbours; expansion adds centre and outer links.", "M3 9h6v6H3zM15 9h6v6h-6M9 12h6M12 3v5M12 16v5"],
	"reaction": ["Reaction", "#f49180", "A visible conditional enemy response after the complete player action and discard chains. Each enemy reacts at most once per action.", "M13 3L4 14h7l-1 7 10-12h-7zM4 4l3 3M17 18l3 3"],
	"intent": ["Intent", "#edba86", "Visible enemy-phase activity. The row activates left to right; new replacements do not add activations to that phase.", "M4 5h16v14H4zM8 9h8M8 13h5M18 2v6M6 2v6"],
	"on_play": ["On Play", "#b3e5d4", "Resolves when this physical card is played into the circle. Retained cards do not replay it.", "M4 3h12v18H4zM10 8l7 4-7 4z"],
	"front": ["Front", "#e4c276", "Front position: faces the enemy. Enemy Front and Rear normally attack player Front."],
	"upper": ["Upper", "#8bcbe2", "Upper Middle position of the formation diamond."],
	"lower": ["Lower", "#8bcbe2", "Lower Middle position of the formation diamond."],
	"rear": ["Rear", "#a4b7ce", "Rear position: Short attacks cannot originate here or target it."]
}
const ALIASES := {"costs":"cost","stunned":"stun","confused":"confuse","attacks":"attack","guard":"guard","manoeuvre":"manoeuvre","maneuvre":"manoeuvre","movement":"manoeuvre","move":"manoeuvre","swap":"manoeuvre","support":"support","mana crystal":"mana","mana crystals":"mana","crystals":"mana","crystal":"mana","hp":"hull","healing":"repair","heal":"repair","repaired":"repair","recovery":"revive","revival":"revive","shield":"shields","armour mitigation":"armour","armor":"armour","resources":"resource","neighbours":"adjacent","neighbor":"adjacent","neighbour":"adjacent","reactions":"reaction","stance":"intent","stances":"intent","enemy phase":"intent","upper middle":"upper","lower middle":"lower","on play":"on_play"}

static func key(word: String) -> String:
	var lower := word.to_lower()
	return ALIASES.get(lower, lower)

static func description(id: String) -> String:
	return DEFINITIONS[id][0] + " — " + DEFINITIONS[id][2] if DEFINITIONS.has(id) else id

static func texture(id: String, enemy_position: bool = false) -> Texture2D:
	if POSITION_GLYPHS.has(id):
		# The player glyphs highlight Front on the right. Enemy Front is on the left.
		var position: String = {"front": "rear", "rear": "front"}.get(id, id) if enemy_position else id
		return POSITION_GLYPHS[position]
	if textures.has(id): return textures[id]
	var entry: Array = DEFINITIONS.get(id, DEFINITIONS.resource)
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24"><rect x="0.5" y="0.5" width="23" height="23" rx="5" fill="#10212c"/><path d="%s" fill="none" stroke="%s" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round"/></svg>' % [entry[3],entry[1]]
	var bitmap := Image.new()
	bitmap.load_svg_from_string(svg)
	textures[id] = ImageTexture.create_from_image(bitmap)
	return textures[id]

static func parts(text: String) -> Array:
	if matcher == null:
		var words: Array = DEFINITIONS.keys() + ALIASES.keys()
		words.erase("on_play")
		words.sort_custom(func(a,b): return a.length() > b.length())
		matcher = RegEx.new()
		matcher.compile("(?i)\\b(" + "|".join(words) + ")\\b|\\b(?:A|W|C)(?=\\d)|\\bSH\\b")
	var result: Array = []
	var offset := 0
	for found in matcher.search_all(text):
		if found.get_start() > offset: result.append({"text":text.substr(offset,found.get_start()-offset)})
		var word: String = found.get_string()
		var id: String = {"A":"armour","W":"weapon","C":"cover","SH":"shields"}.get(word,key(word))
		result.append({"icon":id,"text":word})
		offset = found.get_end()
	if offset < text.length(): result.append({"text":text.substr(offset)})
	return result

static func has_keywords(text: String) -> bool:
	return parts(text).any(func(part): return part.has("icon"))
