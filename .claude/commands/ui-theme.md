# /ui-theme — Generate Godot Theme Resource

Generate a Godot Theme resource (`.tres`) for Roots of Reason.

## Input

$ARGUMENTS — theme scope or element (e.g., "base game theme", "tech tree panel", "dark HUD")

## Instructions

1. **Read existing UI code** and any `.tres` theme files under `assets/themes/` to understand current visual style.

2. **Read ADR-002 in `AGENTS.md`** for visual style constraints:
   - 128x64 isometric tile size, 2x sprite scale contract
   - Player colors: `#2E86DE` (blue), `#E74C3C` (red), `#1ABC9C` (teal), `#F39C12` (orange)
   - These colors must remain readable against any theme background

3. **Design the theme resource** with consistent design tokens:
   - **Font sizes:** establish a hierarchy (HUD labels, panel headers, body text, tooltips)
   - **Color palette:** complement (not clash with) player colors from ADR-002
   - **Panel StyleBox:** define margins, corner radius, background colors/transparency
   - **Button StyleBox:** normal, hover, pressed, disabled states
   - **Spacing:** consistent margins and padding values

4. **Generate the `.tres` theme resource file** at `assets/themes/{name}.tres`:
   - Use Godot's theme resource format
   - Include all standard control types that the theme covers
   - Document design tokens in a comment block at the top of the file

5. **Generate a GDScript helper** if needed for dynamic theme application:
   - Place at `scripts/ui/{name}_theme.gd`
   - Include methods for applying the theme to node trees
   - Follow project conventions (typed variables, tabs, doc comments)

6. **Document the theme's design tokens** in a comment block within the `.tres` file:
   - Color palette with hex values and usage
   - Font size scale
   - Spacing/margin values
   - Any special styling notes

7. **Report** what was generated:
   - List all created file paths
   - Summarize the design token choices
   - Note which control types are themed
   - Describe how to apply the theme to a scene
