# /hud — Generate HUD/UI Element

Generate a HUD or UI element for Roots of Reason.

## Input

$ARGUMENTS — description of the HUD element (e.g., "resource bar", "unit info panel", "minimap")

## Instructions

1. **Read existing HUD code** at `scripts/prototype/prototype_hud.gd` and any UI scripts under `scripts/ui/` to understand current patterns and avoid duplication.

2. **Read relevant data schemas** from `data/` (resource types, unit stats, building stats) to understand what data the HUD element needs to display.

3. **Design the scene tree** for the HUD element:
   - Use `CanvasLayer` (layer 10) as the root pattern for HUD elements
   - Plan the node hierarchy (containers, labels, progress bars, etc.)
   - Consider responsive layout using Godot's container system

4. **Generate the script** following project conventions exactly:
   - **Programmatic node creation** — no `.tscn` for UI (matching existing pattern in `prototype_hud.gd`)
   - **`setup()` dependency injection pattern** — accept autoload references as parameters
   - **Typed variables** — use static typing for all declarations
   - **Tab indentation**, 120-char max line length
   - **Signal connections** for reactive updates (connect to `ResourceManager.resources_changed`, etc.)
   - **All display values from autoloads**, never hardcoded gameplay numbers
   - **Doc comment** on the line after `extends`
   - Place the script at `scripts/ui/{element_name}.gd`

5. **Generate test file** following the same conventions as `/gdtest`:
   - Place at `tests/ui/test_{element_name}.gd`
   - Extends `GdUnitTestSuite`
   - Test public methods, signal connections, initial state
   - Use `auto_free()` for node lifecycle management

6. **Run the linter** on generated files:
   ```bash
   .venv-gdtoolkit/bin/gdlint <files>
   .venv-gdtoolkit/bin/gdformat --check <files>
   ```
   Fix any issues found.

7. **Report** what was generated:
   - List all created file paths
   - Describe the scene tree structure
   - List signal connections made
   - Note any autoload dependencies
