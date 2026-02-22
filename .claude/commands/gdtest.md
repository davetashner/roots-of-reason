# /gdtest — Generate GdUnit4 Test Suite

Generate a comprehensive GdUnit4 test suite for the given GDScript file.

## Input

$ARGUMENTS — path to a GDScript file (e.g., `scripts/autoloads/game_manager.gd`)

## Instructions

1. **Read the target script** at the path provided in $ARGUMENTS. Understand its class name, extends type, exported properties, signals, constants, and public methods.

2. **Determine the test file path.** Mirror the directory structure under `tests/`. For example:
   - `scripts/autoloads/game_manager.gd` → `tests/autoloads/test_game_manager.gd`
   - `scripts/prototype/iso_utils.gd` → `tests/prototype/test_iso_utils.gd`
   - `scripts/map/pathfinder.gd` → `tests/map/test_pathfinder.gd`

   The test file name is always `test_` + the original file name.

3. **Generate the test suite** following these project conventions exactly:

   - **Extends:** `extends GdUnitTestSuite`
   - **Doc comment:** `## Tests for <ClassName>.` on the line after extends
   - **Blank lines:** Two blank lines between each function (matching project style)
   - **Function naming:** `func test_<descriptive_name>() -> void:`
   - **Indentation:** Tabs (not spaces)
   - **Typed assertions** — use the correct GdUnit4 assert for each type:
     - `assert_int(expr)` for integers
     - `assert_float(expr)` for floats
     - `assert_str(expr)` for strings
     - `assert_bool(expr)` for booleans
     - `assert_vector(expr)` for Vector2/Vector3/Vector2i/Vector3i
     - `assert_array(expr)` for arrays
     - `assert_object(expr)` for objects and nodes
     - `assert_signal(obj)` for signal assertions
   - **No `@onready` or `_ready` in tests** — use `before()` / `before_test()` / `after()` / `after_test()` lifecycle hooks if setup is needed
   - **For autoloads** (singletons in project.godot): access them directly by their global name (e.g., `GameManager.current_age`). Save and restore any mutated state.
   - **For class_name scripts**: instantiate directly (e.g., `var utils := IsoUtils.new()`) or call static methods directly
   - **For Node-based scripts**: use `auto_free(node)` to manage lifecycle, or scene_runner for integration tests
   - **Line length:** max 120 characters

4. **What to test** (aim for thorough coverage):
   - All public methods — happy path and edge cases
   - All constants and exported properties — verify initial values
   - Signal emissions where applicable
   - Boundary conditions (empty arrays, zero values, negative inputs)
   - State mutations and their side effects

5. **Write the test file** to the determined path. Create any intermediate directories if needed.

6. **Run the linter** on the new test file: execute `gdlint <test_file_path>` and `gdformat --check <test_file_path>` using the project's gdtoolkit venv at `.venv-gdtoolkit/` (create it with `python3 -m venv .venv-gdtoolkit && .venv-gdtoolkit/bin/pip install 'gdtoolkit==4.*'` if it doesn't exist). Fix any issues.

7. **Report** what you generated: list the test file path, number of test functions, and what aspects of the script are covered.
