# /launch — Launch Game Quick-Start

Launches the game directly into the prototype scene, skipping menus. Defaults to Mesopotamia vs Rome. The debug server is automatically enabled on port 9222 for screenshot capture, game status queries, and sending commands.

## Input

$ARGUMENTS — optional civilization ID (e.g., `polynesia`). Defaults to `mesopotamia`.

## Instructions

1. **Launch the game** by running in the background:

   ```bash
   godot --path <project-root> --scene res://scenes/prototype/prototype_main.tscn -- --quick-start <civ> --debug-server
   ```

   Where `<civ>` is $ARGUMENTS if provided, otherwise `mesopotamia`.

   This bypasses the main menu and lobby. The `--quick-start` flag tells `prototype_main.gd` to auto-set the player civ (and default the AI to Rome), skipping the civ selection screen. The `--debug-server` flag activates the debug HTTP server on `127.0.0.1:9222`.

2. Report that the game is launching with the selected civilization and that the debug server is available at `http://127.0.0.1:9222`. Mention that `./tools/ror screenshot`, `./tools/ror game-status`, and `./tools/ror game-cmd` can be used to interact with the running game.
