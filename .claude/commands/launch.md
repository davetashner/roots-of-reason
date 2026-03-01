# /launch — Launch Game Quick-Start

Launches the game directly into the prototype scene, skipping menus. Defaults to Mesopotamia vs Rome at 3x speed. The debug server is automatically enabled on port 9222 for screenshot capture, game status queries, and sending commands.

## Input

$ARGUMENTS — optional arguments. Supports:
- A civilization ID (e.g., `polynesia`). Defaults to `mesopotamia`.
- `speed=N` to set game speed (e.g., `speed=5`). Defaults to `3`.

Examples: `/launch`, `/launch polynesia`, `/launch speed=5`, `/launch rome speed=2`

## Instructions

1. **Parse arguments** from $ARGUMENTS:
   - Extract `speed=N` if present (default: `3`)
   - Any other non-flag argument is the civilization ID (default: `mesopotamia`)

2. **Launch the game** by running in the background:

   ```bash
   godot --path <project-root> --scene res://scenes/prototype/prototype_main.tscn -- --quick-start <civ> --debug-server
   ```

   Where `<civ>` is the parsed civilization ID.

   This bypasses the main menu and lobby. The `--quick-start` flag tells `prototype_main.gd` to auto-set the player civ (and default the AI to Rome), skipping the civ selection screen. The `--debug-server` flag activates the debug HTTP server on `127.0.0.1:9222`.

3. **Wait for the debug server** to become available by polling `./tools/ror game-status` (retry a few times with short sleeps if needed).

4. **Set game speed** by running:

   ```bash
   ./tools/ror game-cmd speed value=<speed>
   ```

5. Report that the game is launching with the selected civilization at Nx speed and that the debug server is available at `http://127.0.0.1:9222`. Mention that `./tools/ror screenshot`, `./tools/ror game-status`, `./tools/ror game-cmd`, and `./tools/ror scenario` can be used to interact with the running game.
