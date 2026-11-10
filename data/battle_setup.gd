extends RefCounted
## Fixed GDD content. Numeric fields drive rules; strings describe the same effects.

const SHIPS := [
	{"id": "bastion", "name": "Bastion", "role": "BULWARK", "hull": 28, "color": "#d8b477"},
	{"id": "kestrel", "name": "Kestrel", "role": "GUNSHIP", "hull": 20, "color": "#79b9d0"},
	{"id": "lamplighter", "name": "Lamplighter", "role": "TENDER", "hull": 18, "color": "#91c8ad"},
]
const CARDS := {
	"brace": {"name": "Brace for Impact", "owner": 0, "cost": 1, "pays": 2, "ranks": "1–2", "allowed_ranks": [1, 2], "tags": "Guard", "tag_ids": ["Guard"], "effect": "Gain 8 guard."},
	"advance": {"name": "Shield Advance", "owner": 0, "cost": 1, "pays": 1, "ranks": "Any", "allowed_ranks": [1, 2, 3], "tags": "Attack · Movement", "tag_ids": ["Attack","Movement"], "effect": "Deal 4 damage. Then swap with a neighbouring ship."},
	"escort": {"name": "Escort Screen", "owner": 0, "cost": 1, "pays": 1, "ranks": "Any", "allowed_ranks": [1, 2, 3], "tags": "Guard", "tag_ids": ["Guard"], "effect": "Give another surviving ship 6 guard."},
	"broadside": {"name": "Broadside", "owner": 1, "cost": 2, "pays": 1, "ranks": "1–2", "allowed_ranks": [1, 2], "tags": "Attack", "tag_ids": ["Attack"], "effect": "Deal 9 damage."},
	"salvo": {"name": "Piercing Salvo", "owner": 1, "cost": 3, "pays": 2, "ranks": "2–3", "allowed_ranks": [2, 3], "tags": "Attack", "tag_ids": ["Attack"], "effect": "Deal 14 damage."},
	"strafe": {"name": "Strafing Pass", "owner": 1, "cost": 0, "pays": 1, "ranks": "Any", "allowed_ranks": [1, 2, 3], "tags": "Attack · Movement", "tag_ids": ["Attack","Movement"], "effect": "Deal 3 damage. Then swap with a neighbouring ship."},
	"patch": {"name": "Emergency Patch", "owner": 2, "cost": 1, "pays": 2, "ranks": "2–3", "allowed_ranks": [2, 3], "tags": "Repair", "tag_ids": ["Repair"], "effect": "Restore 4 hull to any surviving ship."},
	"relay": {"name": "Signal Relay", "owner": 2, "cost": 0, "pays": 1, "ranks": "Any", "allowed_ranks": [1, 2, 3], "tags": "Tactic", "tag_ids": ["Tactic"], "effect": "Draw two cards, then discard one card from hand if able."},
	"tow": {"name": "Towline Manoeuvre", "owner": 2, "cost": 1, "pays": 1, "ranks": "2–3", "allowed_ranks": [2, 3], "tags": "Movement · Guard", "tag_ids": ["Movement","Guard"], "effect": "Swap a neighbouring pair. Give each ship in that pair 2 guard."},
}
const OPENING_HAND := ["advance", "tow", "escort", "salvo", "brace", "broadside", "patch"]
const COPIES_PER_CARD := 2
const MONSTER := {"name": "Stormmaw", "hull": 70}
const REACTIONS := [
	{"name": "Buffeting Wings", "trigger": "After an action with the Movement tag", "effect": "Deal 3 damage to the acting ship."},
	{"name": "Violent Recoil", "trigger": "After an action deals 8+ hull damage to Stormmaw", "effect": "Deal 4 damage to the acting ship."},
	{"name": "Predator’s Lunge", "trigger": "After an Attack finishes with its actor in rank 1", "effect": "Deal 4 damage to the acting ship."},
	{"name": "Aether Scent", "trigger": "After an action restores at least 1 hull", "effect": "Deal 3 damage to the repaired ship."},
	{"name": "Gathering Static", "trigger": "After an action with printed cost 2+", "effect": "Deal 2 damage to every surviving ship."},
	{"name": "Tail Sweep", "trigger": "After an action with the Guard tag", "effect": "Swap frontmost and rearmost ships. A lone survivor takes 3 damage instead."},
]
const INTENTS := [
	{"name": "Rending Bite", "trigger": "At the end of the fleet phase", "effect": "Deal 7 damage to the frontmost ship."},
	{"name": "Forked Lightning", "trigger": "At the end of the fleet phase", "effect": "Deal 4 damage to frontmost and rearmost ships. A lone survivor is hit once."},
	{"name": "Storm Front", "trigger": "At the end of the fleet phase", "effect": "Deal 3 damage to every ship. Then swap frontmost and rearmost survivors."},
	{"name": "Hunting Dive", "trigger": "At the end of the fleet phase", "effect": "Deal 6 damage to the rearmost ship. Move it to rank 1 if it survives."},
]
