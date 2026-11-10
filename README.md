# Aetherpunk Fleet

Godot 4.7 / GDScript / Compatibility renderer. Open `project.godot` and press **F5**.

## Content editor

Choose **Editor** from the main menu.

- **Leviathans:** edit maximum hull, named reactions and intents, starting behaviours, trigger conditions, and ordered effects.
- **Ships:** edit name, role, hull, colour, and the number of each owned card contributed to the shared deck.
- **Cards:** edit owner, cost, payment value, ranks, tags, and ordered effects.
- Search each list; **New**, **Duplicate**, and **Delete** manage entries. Duplicating a ship also duplicates its cards and remaps its loadout.
- The **Battle Setup** panel selects a leviathan and three distinct ordered ships. Choose a random seven-card opening or configure a fixed seven-card hand.
- **Save All** validates the whole draft and replaces `data/content.json`. It does **not** create a Git commit. **Revert Unsaved Changes** restores the last successful save.
- **Save & Test Battle** saves and launches the configured encounter. **Return to Editor** is available during that battle and on its result screens. Retry keeps the playtest return route.
- Leaving the editor or closing the window with unsaved changes offers Save, Discard, and Cancel. Failed validation or file writes preserve the previous save.

IDs are assigned automatically and survive renaming. Deleting referenced content is blocked with a list of loadouts, owners, or setup fields to change first. Moving a card to another owner requires updating its old loadout.

The editor composes existing combat primitives rather than scripts. Card effects include monster damage, actor/chosen-ship guard, repair, adjacent swaps, pair swaps with guard, and draw/discard. Monster effects include ship damage with target rules, end swaps with a lone-ship fallback, and moving the rear survivor forward. A card shares one chosen ship and one movement choice across its effects. Rules text is generated from these definitions.

The default saved content reproduces the GDD matchup: Bastion (28 hull), Kestrel (20), and Lamplighter (18) versus Stormmaw (70), an 18-card deck, and the original fixed opening. Newly edited loadouts can have different sizes, with at least seven cards across the fleet.

## Battle

1. Select an action card, then click other cards to mark or unmark payment.
2. Choose any required ship and movement targets.
3. Read the preview and press **Play Card**. **Cancel** clears the draft without spending cards.
4. Effects resolve in order, then the current qualifying reaction resolves once and is replaced.
5. Draw/discard effects pause for the requested discards, then continue remaining effects before checking the reaction.
6. **Basic Manoeuvre** costs one resource to swap its chosen actor with a neighbour.
7. **End Fleet Phase** resolves the visible intent and expires guard. Optionally mark hand discards, then **Refill Hand** to draw back to seven.

Payment cards never trigger reactions; excess payment is lost. Guard absorbs damage before hull. Destroyed ships leave the formation, but their cards remain usable as payment. A lethal attack wins before the monster reacts. Intent damage escalates by one per round beyond round three.

Cards animate into play and discard. Floating hull/guard changes, animated hull bars, formation movement, and reaction announcements follow ordered public feedback events. Combat inputs lock during playback; navigation can safely cancel it. Previews never draw cards, consume RNG, or reveal replacements early.

Victory and defeat reports show each ship's status, surviving hull against the selected fleet's starting hull, hull percentage, and rounds taken. **Retry Battle** creates a fresh battle from saved content. Debug outcomes are marked as test results.

## Layout

- `data/content.json`: authoritative version-1 content and selected battle setup.
- `scripts/content_catalog.gd`: schema validation, IO, generated text, and battle compilation.
- `scripts/content_store.gd`: saved content and editor navigation context.
- `scripts/content_editor.gd`: native Godot editor widgets and draft management.
- `scripts/battle_state.gd`: content-driven rules and detached battle snapshots.
- `scripts/battle.gd` and `scripts/combat_feedback.gd`: battle UI and animations.
- `tests/fixtures/gdd_content.json`: immutable GDD fixture for regression checks.

The UI targets 1280 × 800, with scrolling for smaller windows. No external assets or libraries are required.

## Validate

With a Godot console executable on PATH:

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/battle_rules.gd
godot --headless --path . --script res://tests/smoke_flow.gd
godot --headless --path . --script res://tests/combat_feedback.gd
godot --headless --path . --script res://tests/results_flow.gd
godot --headless --path . --script res://tests/content_rules.gd
godot --headless --path . --script res://tests/editor_flow.gd
```

Regressions explicitly load the immutable GDD fixture rather than depending on designer edits. Persistence and editor tests write isolated temporary user-data files, never the project content. They cover invalid data, failed saves, reference checks, new entities, compound effects, paused discards, single-entry behaviour decks, fixed/random hands, real edited playtests, return routes, dirty dialogs, and clean retries.

Campaign progression, persistent expeditions, custom effect scripting, and artwork authoring remain future work. No remote or export target is configured. Godot's generated `.godot/` cache and export `build/` directory are ignored by Git.
