# Aetherpunk Fleet

Godot 4.7 project using GDScript and the Compatibility renderer.

## Run

Import `project.godot` in Godot 4.7 and press **F5**.

Main Menu → Start Game → Battle. The battle displays Bastion (28 hull), Kestrel (20), and Lamplighter (18) in front-to-rear formation against Stormmaw (70). The shared opening hand contains seven cards from the GDD's fixed 18-card deck; the active reaction is Buffeting Wings and the enemy intent is Rending Bite.

Click a card, or focus it using Tab, to inspect its effect, owner, cost, payment value, and permitted ranks. Inspection highlights the card without playing or spending it. The opening is fixed for now. Combat resolution, payment, movement, damage, and enemy turns are not implemented.

**Main Menu** returns to port. **Test Win** and **Test Loss** retain the initial outcome flow. Each result screen returns to the main menu. Exit closes the application.

## Layout

- `scenes/game.tscn`: native battle layout, using `scripts/battle.gd`.
- `scenes/components/`: reusable editable ship and hand-card scenes.
- `data/battle_setup.gd`: GDD ship, card, monster, reaction, and intent data.
- `scripts/battle_art.gd`: scalable vector silhouettes drawn with Godot.
- `scenes/main_menu.tscn`, `victory.tscn`, `defeat.tscn`: navigation screens.
- `tests/smoke_flow.gd`: navigation, battle content, and card inspection check.

The battle view targets 1280 × 800. A scroll container keeps all content reachable in smaller windows. No external assets or dependencies are required.

## Validate

With a Godot console executable on your PATH:

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/smoke_flow.gd
```

Godot's generated `.godot/` cache and exported `build/` directory are ignored by Git. No remote or export target is configured.
