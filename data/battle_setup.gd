extends RefCounted
## Fixed GDD opening. Presentation data only; combat resolution is not implemented.

const SHIPS := [
	{"id": "bastion", "name": "Bastion", "role": "BULWARK", "hull": 28, "color": "#d8b477"},
	{"id": "kestrel", "name": "Kestrel", "role": "GUNSHIP", "hull": 20, "color": "#79b9d0"},
	{"id": "lamplighter", "name": "Lamplighter", "role": "TENDER", "hull": 18, "color": "#91c8ad"},
]
const CARDS := {
	"brace": {"name": "Brace for Impact", "owner": 0, "cost": 1, "pays": 2, "ranks": "1–2", "tags": "Guard", "effect": "Gain 8 guard."},
	"advance": {"name": "Shield Advance", "owner": 0, "cost": 1, "pays": 1, "ranks": "Any", "tags": "Attack · Movement", "effect": "Deal 4 damage. Then swap with a neighbouring ship."},
	"escort": {"name": "Escort Screen", "owner": 0, "cost": 1, "pays": 1, "ranks": "Any", "tags": "Guard", "effect": "Give another surviving ship 6 guard."},
	"broadside": {"name": "Broadside", "owner": 1, "cost": 2, "pays": 1, "ranks": "1–2", "tags": "Attack", "effect": "Deal 9 damage."},
	"salvo": {"name": "Piercing Salvo", "owner": 1, "cost": 3, "pays": 2, "ranks": "2–3", "tags": "Attack", "effect": "Deal 14 damage."},
	"strafe": {"name": "Strafing Pass", "owner": 1, "cost": 0, "pays": 1, "ranks": "Any", "tags": "Attack · Movement", "effect": "Deal 3 damage. Then swap with a neighbouring ship."},
	"patch": {"name": "Emergency Patch", "owner": 2, "cost": 1, "pays": 2, "ranks": "2–3", "tags": "Repair", "effect": "Restore 4 hull to any surviving ship."},
	"relay": {"name": "Signal Relay", "owner": 2, "cost": 0, "pays": 1, "ranks": "Any", "tags": "Tactic", "effect": "Draw two cards, then discard one card from hand if able."},
	"tow": {"name": "Towline Manoeuvre", "owner": 2, "cost": 1, "pays": 1, "ranks": "2–3", "tags": "Movement · Guard", "effect": "Swap a neighbouring pair. Give each ship in that pair 2 guard."},
}
const OPENING_HAND := ["advance", "tow", "escort", "salvo", "brace", "broadside", "patch"]
const COPIES_PER_CARD := 2
const MONSTER := {"name": "Stormmaw", "hull": 70}
const REACTION := {"name": "Buffeting Wings", "trigger": "After an action with the Movement tag", "effect": "Deal 3 damage to the acting ship."}
const INTENT := {"name": "Rending Bite", "trigger": "At the end of the fleet phase", "effect": "Deal 7 damage to the frontmost ship."}
