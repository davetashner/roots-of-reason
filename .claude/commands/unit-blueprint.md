# /unit-blueprint — Generate Unit Blueprint JSON

Generate a complete blueprint JSON file for the MakeHuman-based unit creation pipeline from a natural language description.

## Input

$ARGUMENTS — unit name and description in the format: `<name> - <description>`

Example: `clubman - prehistoric hunter-gatherer with wild dark hair, fur pelt over one shoulder, leather loincloth, wielding a wooden club`

## Instructions

1. **Parse the input.** Extract the unit name (before the `-`) and the description (after the `-`). The name must be snake_case.

2. **Read the blueprint schema** at `blender/blueprints/schema.json` to understand all available fields.

3. **Read existing blueprints** in `blender/blueprints/` for reference (archer.json, infantry.json, clubman.json).

4. **Check installed MPFB2 assets** by reading `blender/assets_installed.json`. These clothing/equipment assets are available for use.

5. **Generate the blueprint JSON** following these guidelines:

   ### Body Parameters
   | Parameter | Range | Guidance |
   |-----------|-------|----------|
   | gender | 0-1 | 0 = female, 1 = male. Most military units are 1.0. |
   | age | 0-1 | 0 = young (teen), 0.3-0.5 = prime warrior, 0.7+ = elder |
   | muscle | 0-1 | 0.3 = lean, 0.6 = fit, 0.8 = muscular, 1.0 = bodybuilder |
   | weight | 0-1 | 0.3 = thin, 0.5 = average, 0.7 = stocky, 1.0 = heavy |
   | height | 0-2 | 1.0 = default, 0.8 = short, 1.2 = tall |
   | decimate_ratio | 0.05-1 | 0.25 = standard, 0.5 = higher detail (if clothing needs it) |

   ### Hair Styles
   - `"wild"` — Large displacement, rough surface. Good for prehistoric/barbarian units.
   - `"short"` — Small displacement, clean. Good for soldiers, modern units.
   - `"long"` — Extended cap, smoother. Good for mages, nobles.
   - Hair color: dark brown `[0.08, 0.05, 0.03, 1.0]`, black `[0.02, 0.02, 0.02, 1.0]`, red `[0.4, 0.1, 0.02, 1.0]`, blonde `[0.6, 0.45, 0.2, 1.0]`, grey `[0.4, 0.4, 0.4, 1.0]`

   ### Clothing
   Use MPFB2 community assets when available (check assets_installed.json):
   - `player_colored: true` — magenta with shading, tinted to player color in-game
   - `color: [r, g, b, a]` — fixed color (leather brown, fur color, etc.)

   Key available community clothing (when installed):
   - `rehmanpolanski_viking_tunic` — good for medieval/primitive upper body
   - `rehmanpolanski_viking_pants` — leg covering
   - `rehmanpolanski_viking_boots` — foot covering
   - `drednicolson_asymmetric_tunic_and_sash` — asymmetric, great for primitive look
   - `donitz_monk_robe` — full-body robe
   - `joepal_crude_high_socks` — primitive boot/leg wraps
   - `toigo_leg_warmer_socks` — leg warmers

   Fall back to legacy `"loincloth"` for minimal clothing.

   ### Equipment Templates
   Built-in (procedural geometry):
   - `bow` — parent to `hand_l`
   - `quiver` — parent to `spine_02`
   - `sword` — parent to `hand_r`
   - `shield` — parent to `hand_l`
   - `spear` — parent to `hand_r`
   - `club` — parent to `hand_r`

   MakeHuman community (when installed, use `mhclo:` prefix):
   - `mhclo:culturalibre_wooden_bow` — more detailed bow
   - `mhclo:joepal_crude_sword` — rough sword
   - `mhclo:culturalibre_war_hammer` — hammer weapon

   ### Animations
   - `"ranged"` — for bow/ranged units
   - `"melee"` — for sword/club/spear units
   - Standard frame counts: `{"idle": 4, "walk": 8, "attack": 6, "death": 6}`

   ### Tabard (Player Color Marker)
   Every unit needs a tabard for the player color shader. Common configs:
   - Chest tabard: `{"parent_bone": "spine_02", "scale": [0.22, 0.12, 0.25]}`
   - Arm band: `{"parent_bone": "upperarm_l", "scale": [0.06, 0.06, 0.04]}`
   - If using `player_colored` clothing, the tabard can be smaller (arm band).

   ### Stats Template
   - `"ranged"` — for ranged units
   - `"melee"` — for melee units

6. **Write the blueprint** to `blender/blueprints/<name>.json`.

7. **Validate** the JSON against the schema structure. Ensure all required fields are present.

8. **Report** what you generated: the file path, key choices made (clothing, equipment, hair style), and any notes about assets that need to be installed first.
