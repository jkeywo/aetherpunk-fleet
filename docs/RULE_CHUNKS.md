# Composable combat rules

`scripts/rules/rule_registry.gd` registers six component families: triggers, conditions, costs, effects, modifiers, and calculated values. Selector fields are typed by each chunk. Group selectors can be narrowed with an effect's `filter` condition; `event_target` identifies the candidate unit while filtering. Card type, trait, and ID filters remain separate.

Each entry owns its stable ID, typed fields/defaults, compatible target/zone/context metadata, generated description, and handler. Add a code chunk once, then combine it in cards, ship resources, upgrades, captains, and enemy stances. No content-name dispatch or executable strings are used.

## Rule data

```json
{
  "id": "adjacent_attack_protection",
  "zone": "circle",
  "trigger": { "kind": "adjacent_card_played", "card_type": "Attack", "subject": "adjacent" },
  "conditions": { "all": [
    { "kind": "resource_at_least", "target": "owner", "amount": 2 }
  ] },
  "costs": [{ "kind": "ship_resource", "target": "owner", "amount": 2 }],
  "effects": [{ "kind": "add_shields", "target": "event_actor", "amount": 3 }],
  "modifiers": [],
  "limit": "once_per_action",
  "optional": false
}
```

New cards have exactly one primary type (Attack, Guard, Manoeuvre, Support) and 1–3 blocks, including On Play. Shipped ships have two starter designs (one effect and two effects), level-2 upgrades use two, level-3 upgrades use three, and captain cards use one effect per tier. New editor cards start with one effect. `zone` controls card activity: circle, hand, discard, discard_top, or any exposed zone. Ship/captain/upgrade blocks use their corresponding context and are inactive while their owner is defeated. A passive trigger uses modifiers; event triggers use effects and optional resource costs. Automatic responses use owner, event, and group selectors; explicit ally/circle/stance/reaction choices belong to pending On Play rules and boosts. Reactive attacks inherit the action's chosen enemy, falling back to the first legal enemy when none was chosen. Incompatible contexts fail validation.

Conditions accept registered `all`/`any`/`not` chunks or their object shorthand. Values accept nonnegative constants or registered calculations: weapon damage (including upgrades), resource totals, missing hull, adjacent matches, sum, product, min, and max. Arithmetic is bounded to 0–99999, with a nesting limit of 16.

Modifier amounts add to their named statistic; cost amounts are discounts floored at zero. Weapon range selects Short or Long. Fleet mana modifiers target `fleet`. Damage can target the owning unit or a card domain explicitly; attack_damage applies on the first hit, per_hit_damage on every hit. The rule's conditions provide scope. For candidate-sensitive filtering, use the effect's group filter or a modifier's card_type/trait fields.

## Event and queue contracts

- Events carry kind, actor, target, physical card UID, card definition, position, amount, metrics, and causal ancestry. Damage separates cover absorption, armour mitigation, shield absorption, and actual hull loss. Repair events report actual restoration and identify the repairing actor separately from the recipient.
- Card UIDs distinguish physical copies sharing a design ID. A source key includes its UID/rule ID or ship/rule index. Rule usage is marked when queued. Default limits are once per physical rule per completed action; per-turn and per-hit variants are explicit. A rule cannot re-enter its own causal ancestry.
- Queue ordering is deterministic: owning On Play blocks and their ordered effects, allied FIFO event chains, committed payment discards and their FIFO chains, then one reaction per enemy in formation order. Main On Play conditions evaluate when their block runs, allowing earlier movement to change position checks. Event-response eligibility is latched when queued; affordability is checked before execution.
- Optional boosts reserve personal resources before automatic rules evaluate. Pending circle actions remain detached until the required costs and direct-click targets are complete, then commit automatically. Basic drag/drop actions commit on release. A cancelled draft emits no game events.
- Freeze eligible visible stance UIDs at action commitment. Replacing a card removes its eligibility even if a one-card deck immediately reveals the same physical UID. Enemy-phase activations likewise use a frozen row; replacements never add activations.
- Mandatory discard and scry hold the remaining queue and causal context. Resuming a decision keeps usage and ancestry. Automatic circle cleanup emits no committed-discard event.
- A killing hit removes the defeated enemy's contributions immediately, but the remaining allied effects and payment responses finish before victory is reported. Fleet destruction ends the encounter.
- Previews clone world state, snapshots, and RNG. Hidden operations are marked uncertain and do not reveal identities or consume live RNG. Preview state is never committed.

## Extending a mechanic

1. Register a stable chunk ID with typed parameter fields and compatible targets.
2. Supply its generated description and handler. Keep the primitive reusable; data supplies content-specific numbers and conditions.
3. Use the existing executor/event protocol for state changes and feedback. Decision effects return control with a pending context and resume the same queue.
4. The generic Spec/Rule editors render the registry schema. Add no card-specific forms.
5. Extend registry checks and behavior regressions. Test public preview parity, causal limits, and physical card conservation where relevant.

`content_v2.gd` and `content_legacy.gd` are import adapters and immutable-fixture validators. They do not execute live battle abilities. Migration preserves legacy target patterns and adjacent pair swaps through registered parameters/selectors; new enemy content uses deterministic matching-position targeting.


Common enemy reactions use the registered `reaction_trigger` condition chunk, with `family` of `card_type`, `position`, `damaged`, or `healed`. Only type and position have a choice parameter. Origin positions are captured when a card commits: Front=0, Upper Flank=1, Lower Flank=2, Rear=3. Type and position conditions require a genuinely played card; basic costs and payment discards do not count. Damaged means this enemy actually loses hull, and healed means a player ship regains hull (including basic repair/revival). All checks still happen after the completed action and its chains. Existing legacy condition trees continue to load unchanged, and the enemy editor offers four common families plus Custom trigger. Custom mode persists `custom_trigger: true`, exposes the full condition tree, and renders the old text layout.

Reaction art lives in `assets/generated/reactions/`. `reaction_badge.gd` draws the shared imagegen frame around the existing card-type glyph or the generated position/damage/heal glyph. Standalone position glyphs use the player formation (Front right, Rear left). On reaction cards, `monster_portrait.gd` draws the position glyph behind the owning monster and mirrors it for enemy facing: Front left, Rear right, Upper/Lower Flanks up/down. Damage uses the Stormmaw leviathan, not an airship. Tooltips supply full trigger text. Row cards and enlarged presentations carry a detached `owner_visual` definition and reuse the same rig art as the owning monster.


## Area effects

`beam` is an attack with configurable `damage`, `hits`, and `range` (`weapon`, `Short`, or `Long`). It needs no target click. Resolve its lane using the attacker's current position after preceding movement: Front/Rear hits occupied opposing Front and Rear; Upper/Lower hits only the matching flank. Empty positions do not block it. Short range still cannot originate from Rear or hit Rear. Each victim receives its own normal attack and per-hit cover/armour/shields calculation; first-hit bonuses apply once per victim.

`explosion` selects a main unit (`target`, normally `chosen_enemy`) and has a range plus two independently ordered lists: `main_effects` and `adjacent_effects`. Lock the main and occupied adjacent unit identities when the explosion starts. Complete main effects first, then apply the splash list separately to each neighbour in formation order. Defeating the main unit does not cancel splash; empty positions and defeated victims are skipped. A short explosion cannot originate from Rear or affect Rear. Nested attacks also respect their own range. The area queue supports normal draw/discard/scry suspension and resumes with the same bound targets.

Inside those lists, `area_target` means the current main/splash unit. For Stun, `area_reaction` selects that unit's first unstunned visible reaction in row order; it suppresses one reaction for the fleet phase and has no effect if none is visible. Main-target stun and splash damage can therefore be authored independently:

```json
{
  "kind": "explosion",
  "target": "chosen_enemy",
  "range": "Long",
  "main_effects": [
    {"kind": "attack", "target": "area_target", "damage": 6, "hits": 1, "range": "Long"},
    {"kind": "stun", "target": "area_reaction"}
  ],
  "adjacent_effects": [
    {"kind": "attack", "target": "area_target", "damage": 2, "hits": 1, "range": "Long"}
  ]
}
```

Both chunks appear in the generated effect editor. Each explosion list has Add effect, Remove, Up, and Down controls. Nested chunks retain validation and context restrictions. Both run through detached previews, normal trigger limits, payment/cancellation, and post-action monster reactions. Beam has a sustained cyan line through its victims; explosion has an orange projectile, shockwave, and radial sparks. Area feedback groups its visual while each victim keeps normal damage, defence, and hull-loss flash feedback. Keyword icons and tooltips distinguish both patterns. Existing content and immutable fixtures are unchanged.


## Attack origins and presentation

Visual rigs have an optional `markers` list: each point has a unique `id`, a `part` ID, and normalized `uv: [u,v]`. Its position follows that part's live pose, including parent transforms, flips, rotations, rig fitting, and viewport scaling. Shipped rigs define `attack` on the bow/head and `impact` on the body. Legacy/custom rigs without markers use the root's facing edge for attacks and its centre for impacts. An unknown origin falls back to `attack`, then that facing edge.

In **Sprites & animation**, add/remove named points, choose a sprite part, and edit U/V. **Drag marker** selects marker mode; drag in the assembly preview to place it. Cyan crosses follow their parts through idle animation. Part deletion is blocked until its markers are moved or removed. Apply changes the workshop draft; Save All persists it. Rigs and attack effects remain detached in running battles.

All three attack primitives (`attack`, `beam`, `explosion`) accept:

- `presentation`: `auto`, `ranged`, `beam`, `explosion`, or `melee`.
- `origin_marker`: a marker name, default `attack`.

These fields configure feedback only. Short/Long range, beam lanes, blast adjacency, damage, and reaction timing are unchanged. Auto makes monster attacks melee; player attacks use projectile, beam, or explosion according to their primitive. Explicit presentation overrides auto for either side. For example, a player ram:

```json
{"kind":"attack", "target":"chosen_enemy", "damage":{"kind":"weapon_damage","target":"owner"}, "hits":1, "range":"Short", "presentation":"melee", "origin_marker":"attack"}
```

Melee hides source artwork, moves a detached copy along a curved path until its chosen marker contacts the target/defence, shows an impact, then returns and restores the source. Formation, labels, cover, and shields stay in their slots. A multi-target melee presentation visits each locked victim; ordinary hits retain their damage feedback. The transient copy does not alter battle state or RNG. Beam/explosion presentations also work for a single-target attack. A child attack in an explosion can explicitly request its own presentation; otherwise it shares the enclosing blast visual.
