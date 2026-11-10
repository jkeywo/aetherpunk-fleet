# Aetherpunk Fleet

Godot 4.7 / GDScript / Compatibility renderer. Open `project.godot` and press **F5**.

## Diamond battle

The battle follows the supplied layout: allied diamond left, enemy diamond right, a magic circle above the fanned shared hand, and deck/discard piles in the lower corners. Front faces the opponent. Each side has **Front, Upper Middle, Lower Middle, Rear** positions. Three allied ships and one leviathan are supported; empty slots persist after movement and destruction.

Select a card, choose an empty unlocked circle slot, click other hand cards as payment, and **Play Card**. Target and movement selectors appear where needed. Hover cards or occupied circle slots for complete rules. **Cancel** clears the draft. **Manoeuvre** costs one resource to move into an adjacent empty position or swap with its occupant.

The gear opens a pausing battle menu with Resume, Main Menu, and Return to Editor during playtests. History shows recent resolution messages. Input locks during animations; menu navigation safely cancels playback.

Drag a hand card onto the circle as an alternative to clicking. Available destinations have blue **DROP HERE** outlines; hover turns the destination gold and highlights green **BONUS** sources and links. The preview recalculates adjacency, discounts, conditions, and available payment for that slot. Occupied, locked, unaffordable, and position-restricted destinations reject the drop. Dropping selects the action and destination: choose payment and targets, then press **Play Card**. Dropping outside or onto an invalid slot preserves the previous draft. Dragging the selected card keeps payment when still needed and clears it if the new slot makes the action free. Dragging is unavailable during resolution, mandatory discard, or hand refresh.

### Magic circle

The first four slots are North, East, South, and West, connected in a diamond. Filling them unlocks Centre and four outer corners. The fourth card and its complete allied chain resolve using the original graph; expansion happens afterward, before the monster reaction.

Expansion keeps the original links. Centre touches all four original slots. Each corner touches its two neighbouring original points. Original slots consequently have five neighbours after expansion. Any empty unlocked slot can receive a card, with a maximum of nine plays resident at once. A full circle still permits manoeuvres and ending the phase.

Played cards stay in the circle through the enemy phase. They are discarded at the next player-turn start, when the circle contracts and trigger usage resets. Payment cards are discarded after action resolution. Circle cleanup and payment never fire card triggers. All physical card instances remain conserved across hand, deck, discard, circle, and held payment.

### Conditions, modifiers, and chains

Cards can have:

- **Conditional on-play effects** enabled by counts of adjacent card tags.
- **Ongoing neighbour modifiers** adding damage, guard, or healing, or reducing the cost of a neighbouring incoming card. Reductions floor cost at zero; monster reactions that check printed cost use the original value.
- **Triggered effects** watching neighbouring card plays or card-caused damage, guard, healing, draws, mandatory discards, and movement.

Resolve the played card first, then process triggered effects in FIFO order, with ties broken by card play order and rule order. Effects can trigger other eligible cards. Each rule on each physical card instance can fire **once per turn**, marked used when queued to prevent loops. Continuous modifiers remain active after triggers are used and do not emit events.

When a card and destination slot are selected, contributing neighbours have a green **BONUS** badge, a bright border, and a green link to the selected gold slot. Other occupied neighbours remain purple. Hover a bonus source for its cost/damage/guard/healing contribution or the conditional effect it enables. These public bonuses stay visible while payment or target choices are incomplete.

As each chained effect resolves, a directional spark travels from the card that caused the event to the reacting card, with both endpoints outlined. Damage links are orange, guard links blue, repair links green, and other event links purple. The chain banner names both cards and the triggering event. Pulses follow the resolution queue, pause with the battle menu, and clear when finished.

Triggered effects have automatic source/event-actor targets and no new movement prompts. Draw/discard effects pause the queue for player choices, then resume without resetting usage. Destroyed ships cannot receive guard or repairs; stored in-circle magic remains until cleanup. Previews simulate public effects without consuming real RNG, drawing hidden card identities, or revealing the next stance.

### Enemy stances

Each leviathan has a small shuffled stance deck. Only the current stance is visible. It specifies ordered reaction rules and an enemy-phase effect sequence.

After the full allied action and trigger chain, the first qualifying reaction resolves and immediately changes stance. The new stance cannot react to that same action. Ending the phase executes the current stance's activity, then changes stance again. Draw stances without replacement and reshuffle on exhaustion; a single-stance deck can repeat.

Guard absorbs damage before hull and expires after enemy activity. Intent damage still gains one per round beyond round three. A lethal allied action wins before enemy retaliation.

## Example circle opening

The saved setup starts with four example cards plus Broadside, Brace for Impact, and Signal Relay. The fleet still contributes six cards per ship (18 total). Each example replaces one old copy; every original card remains available. The bundled content is now version 2 so these rules are editable immediately.

| Card | Ship | Cost | Circle mechanic |
| --- | --- | --- | --- |
| Aether Conduit | Lamplighter | 0 | Gain 2 guard. Neighbouring Attack cards gain +2 damage per damage effect; all neighbouring cards cost 1 less. |
| Resonant Bulwark | Bastion | 0 | Gain 2 guard. Once per turn, a neighbouring Attack dealing damage gives its acting ship 3 guard. |
| Arc Echo | Kestrel | 0 | Deal 2 damage. Once per turn, a neighbouring card granting guard makes Arc Echo deal 2 damage. |
| Convergence Bolt | Kestrel | 1 | Deal 3 damage, plus a separate 3-damage effect if adjacent to a Tactic. |

Try this sequence, with no payment cards selected:

1. **Aether Conduit → North.** Lamplighter gains 2 guard.
2. **Resonant Bulwark → East.** Bastion gains 2 guard; its reaction is armed.
3. **Arc Echo → South.** Deal 2 damage, trigger Bulwark to give Kestrel 3 guard, then trigger Arc Echo for 2 more damage. Stormmaw has 66 hull. Both trigger badges are used for this turn.
4. **Convergence Bolt → West.** Adjacent Conduit reduces the cost to zero, enables the Tactic condition, and adds 2 to each damage effect: 5 + 5 = 10 damage. Stormmaw has 56 hull and the circle expands.
5. Optionally play **Broadside → Centre**, paying with **Brace for Impact**. Conduit reduces the cost to 1 and raises damage to 11. The used triggers stay spent. Stormmaw has 45 hull.

These outcomes assume the unmodified opening stance and cards. To compare placement, retry and play Convergence Bolt at South directly after the North Conduit: it costs 1 and deals only 3 damage because the two cards are not adjacent. Hover cards and circle slots for full generated rules. Signal Relay can draw more cards for experimenting with expanded placements; its mandatory discard pauses resolution normally.


## Live content editor

Use **Editor** on the main menu. Its tabs create, duplicate, edit, and delete leviathans, ships, and cards. Stable IDs survive renaming, and referenced entries cannot be deleted until their references are changed.

The right inspector switches between:

- **Preview:** shared in-game card/unit/stance widgets, updated directly from unsaved fields. Card previews offer a mini-circle, expanded layout, destination slot, and neighbouring tag controls. Invalid drafts remain visible with validation messages.
- **Battle Setup:** choose the leviathan, three ships and their distinct positions, the enemy position, and a random or fixed seven-card opening hand.

Leviathans edit named stances, their starting stance, reaction priority and conditions, and enemy-phase activity. Cards edit permitted acting positions, ordered base effects, conditional effects, modifiers, and once-per-turn trigger rules. Ships edit hull, colour, role, and variable card loadouts.

**Save All** validates and writes `data/content.json`; it never creates a Git commit. **Revert Unsaved Changes** restores saved definitions. **Save & Test Battle** launches the saved setup, with Return to Editor in the gear menu and result screen. Editor selection and preview context are remembered in memory.

Leaving the editor or closing the window with a dirty draft offers Save, Discard, and Cancel. Invalid content and failed writes preserve the previous save.

## Content versions

Version 2 defines explicit positions, stances, adjacency conditions, modifiers, and trigger rules. Existing version-1 content is migrated **in memory** and remains unchanged on disk until an explicit Save.

Ranks map as 1 → Front, 2 → both middle positions, 3 → Rear. Existing reaction and intent lists are cycled from their selected starting entries into enough stances to preserve every behaviour. Root ship, card, and leviathan IDs are retained.

`tests/fixtures/gdd_content.json` remains the immutable version-1 fixture. `tests/fixtures/diamond_content.json` freezes the migrated version-2 baseline. Runtime designers can edit project content without changing regression expectations.

Main modules: `content_catalog.gd` (migration/validation/text), `battle_state.gd` (rules), `battle_geometry.gd` (graphs), `battle.gd` (layout/input), `combat_feedback.gd` (animation), and shared `card_face.gd`, `unit_view.gd`, `formation_view.gd`, `circle_view.gd`, and `stance_view.gd`.

## Verification

With the Godot console executable on PATH:

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/battle_rules.gd
godot --headless --path . --script res://tests/content_rules.gd
godot --headless --path . --script res://tests/smoke_flow.gd
godot --headless --path . --script res://tests/combat_feedback.gd
godot --headless --path . --script res://tests/results_flow.gd
godot --headless --path . --script res://tests/editor_flow.gd
godot --headless --path . --script res://tests/circle_examples.gd
godot --headless --path . --script res://tests/circle_feedback.gd
godot --headless --path . --script res://tests/drag_drop.gd
```

Suites cover unchanged payment, guard, repair, conservation, lethal-hit and results rules plus new positions, expansion timing, modifier costs, finite chains, paused discards, independent copies, stance transitions, migration, safe saving, live previews, real playtests, navigation, and animation cancellation. Editor/persistence tests use temporary user-data files and never save project content.

The UI targets 1280 × 800; smaller windows scroll. Multiple enemies, variable fleet sizes, custom scripts, facing/cover bonuses, and campaign progression remain outside this version. No remote or export target is configured.
