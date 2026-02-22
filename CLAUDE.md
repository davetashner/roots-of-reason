# Roots of Reason

A civilization RTS inspired by Age of Empires where the endgame is achieving AGI. Built with Godot 4 + GDScript, 2D isometric, single-player vs AI.

## Key Directories

| Directory | Purpose |
|-----------|---------|
| `scenes/` | Game scenes organized by feature |
| `scripts/` | GDScript files (mirrors `scenes/` structure) |
| `autoloads/` | Global singletons (registered in `project.godot`) |
| `data/` | JSON data files (tech trees, unit stats, civ data) |
| `assets/` | Art, audio, fonts |
| `addons/` | Godot addons (GdUnit4, etc.) |
| `tests/` | Test files (mirrors `scripts/` structure) |

## Conventions

- **Naming:** snake_case for all scripts and files
- **Tests:** `test_` prefix, mirror `scripts/` path into `tests/` (e.g., `scripts/units/unit.gd` -> `tests/units/test_unit.gd`)
- **Autoloads:** Register in `project.godot`, place in `autoloads/`
- **Data-driven:** ALL gameplay numbers go in JSON files under `data/` — never hardcode stats, costs, or rates in scripts
- **Serializable state:** Every system holding game state must implement save/load from day one
- **Language:** GDScript only. C# reserved for proven hot paths after profiling.

## Quality Gates

Run before committing:

```bash
ror test        # Run GdUnit4 tests
ror lint        # Run gdtoolkit lint + format check
ror coverage    # Check 90% line coverage on gameplay scripts
```

Use `/gdtest` skill to generate test suites for new scripts.

## Workflow

- **Never push directly to main** — always create a PR
- **Run `bd sync` before pushing** to keep beads backlog in sync
- **Reference beads issue IDs** in commit messages (e.g., `feat: add camera [roots-of-reason-317.1]`)
- **Run `ror lint` before committing** — CI enforces zero warnings
- **Sign off commits** with `git commit -s`

## Beads (Issue Tracking)

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
bd orphans            # Surface stale blockers
bd blocked            # Show blocked issues
```

## Architecture

See `AGENTS.md` for:
- Full ADRs (001-011) — locked architecture decisions
- Game design details (resources, combat, victory conditions)
- Art pipeline and sprite specifications
- Coding standards with examples
