# Aetherpunk Fleet

Godot 4.7 project using GDScript and the Compatibility renderer.

## Run

Import `project.godot` in Godot 4.7 and press **F6** for the selected scene or **F5** to start at the main menu.

The initial flow is Main Menu → Start Game → Trigger Win / Trigger Loss → Return to Main Menu. Exit closes the application. Buttons support mouse, Tab / Shift+Tab, and Enter / Space.

## Layout

- `scenes/main_menu.tscn`: Start Game and Exit.
- `scenes/game.tscn`: placeholder battle with two outcome buttons.
- `scenes/victory.tscn` and `scenes/defeat.tscn`: result screens.
- `scripts/screen.gd`: shared theme and navigation.
- `tests/smoke_flow.gd`: headless integration check of both outcome paths and Exit.

The screens are native editable Godot Control scenes. No combat or external assets are included yet.

## Validate

With a Godot console executable on your PATH:

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/smoke_flow.gd
```

Godot's generated `.godot/` cache and exported `build/` directory are ignored by Git. No remote or export target is configured.
