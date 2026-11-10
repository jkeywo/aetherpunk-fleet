# Aetherpunk Fleet

Godot 4.7 / GDScript / Compatibility renderer. Open `project.godot` and press **F5**.

## Play

Start Game enters a fixed opening battle: Bastion (28 hull), Kestrel (20), and Lamplighter (18) versus Stormmaw (70). The opening seven-card hand, Buffeting Wings reaction, and Rending Bite intent match the GDD. Remaining decks are shuffled per battle.

1. Click an action card. Click other hand cards to mark or unmark payment.
2. Choose a target or swap in the dropdown when required.
3. Read the public-outcome preview, then **Play Card**. **Cancel** clears the draft without spending anything; click the selected action again to cancel.
4. The effect resolves first, followed by the qualifying current reaction. Its replacement is revealed immediately and waits for another action.
5. **Signal Relay** draws up to two cards and asks you to click one card to discard before continuing.
6. **Basic Manoeuvre** costs one resource and lets the chosen actor swap with a neighbour.
7. **End Fleet Phase** resolves the visible enemy intent and expires guard. Select optional hand discards, then **Refill Hand** to retain the rest and draw to seven.

Cards have unique instance IDs, so duplicates remain independent. Payment cards do not trigger reactions. Overpayment is lost; free cards require no payment. Rank restrictions apply when committing the action. Guard absorbs damage before hull. Destroyed ships leave the formation; their cards remain usable as payment. Lethal attacks win before the monster can react. Fleet destruction loses automatically.

A scrollable action history records payment, effects, damage, reactions, and round changes. The preview simulates public outcomes without drawing cards, revealing replacements, or consuming battle RNG. Escalation adds one enemy-intent damage per round beyond round three. Menu/result navigation and **Test Win / Test Loss** remain available.

Buttons support mouse and keyboard focus with Tab and Enter/Space. The battle targets 1280 × 800; scroll to reach the action history or content in smaller windows.

## Layout

- `data/battle_setup.gd`: ships, all nine card designs (two copies each), six reactions, four intents.
- `scripts/battle_state.gd`: rules, instance IDs, piles, validation, effects, reactions, and previews.
- `scripts/battle.gd`: UI selection, payment, targeting, state rendering, and navigation.
- `scripts/combat_feedback.gd`: node-bound tween playback of ordered public combat events.
- `scenes/game.tscn` and `scenes/components/`: editable native battle layout.
- `scripts/battle_art.gd`: scalable vector silhouettes.

## Validate

With the Godot console executable on your PATH:

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/battle_rules.gd
godot --headless --path . --script res://tests/smoke_flow.gd
godot --headless --path . --script res://tests/combat_feedback.gd
```

Rules tests cover payment validation, preview purity, the worked GDD sequence, card effects, six reaction triggers, Relay reshuffling, destruction, round transitions, and card conservation. UI smoke checks use actual buttons and verify live state, navigation, and automatic outcomes.

Payment cards fly to the discard counter; played cards lift from the hand and move to discard after their effects. Draws and optional discards also animate. Damage, repair, guard gain, guard consumption, and guard expiry have distinct floating labels, flashes, and hull-bar tweens. Formation changes slide between ranks. A highlighted reaction panel and named banner precede reaction effects; the replacement is revealed afterward. Enemy intents are announced before their damage.

Combat inputs are locked throughout feedback to prevent double spending. Main Menu remains available and safely cancels playback. Victory/defeat screens wait until the full sequence finishes. The rules resolve once and provide public snapshots for animation; previews and animations never change battle outcomes or reveal hidden draws early. The feedback test runs real asynchronous tweens with accelerated timing and checks sequencing, input locks, transient cleanup, and navigation cancellation.

 Campaign progression, fleet persistence, and result statistics remain future work. No external dependencies, remote, or export target are configured. Godot's generated `.godot/` and export `build/` directories are ignored by Git.
