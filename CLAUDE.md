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

### GDScript Gotchas

- **Lambda capture:** GDScript lambdas do NOT capture loop variables by value. Use Array or Dictionary containers for signal detection in tests instead of direct variable capture.
- **JSON numerics:** `JSON.parse_string()` loads all numbers as floats. Always cast to `int()` when comparing against integer game values.
- **File length:** Keep files under 1000 lines. Proactively refactor if approaching this limit.
- **Formatter safety:** Run `gdformat` BEFORE running tests to avoid lint-then-revert cycles. Verify inline dictionary calls weren't mangled by the formatter.

## Quality Gates

Run before committing:

```bash
./tools/ror test        # Run GdUnit4 tests
./tools/ror lint        # Run gdtoolkit lint + format check
./tools/ror coverage    # Check 90% line coverage on gameplay scripts
```

> **Note:** `ror` is a local script at `./tools/ror`, not a global command. Always invoke it with the `./tools/` prefix.

Use `/gdtest` skill to generate test suites for new scripts.

- **After creating a new GDScript file**, run `/gdtest <path>` to generate its test suite
- **Available skills:** `/gdtest` (test generation), `/hud` (HUD elements), `/ui-theme` (Godot themes)

### Common Test Failure Causes

When tests fail, check these first before debugging from scratch:

1. **init_player defaults:** `init_player()` provides non-zero starting resources — mock starting resources explicitly in tests
2. **DataLoader overwrites:** `DataLoader` may overwrite values set in test `before()` — set test values after `DataLoader` init or mock the loader
3. **find_nearest_hostile returns null:** Test context may lack required nodes — stub the method or add mock hostiles
4. **Signal monitor cleanup:** Signal monitors attached to singletons cause freeing issues — detach in `after()` or use Array-based detection

## Workflow

- **Explore thoroughly, then implement decisively.** Read existing code and understand integration points before writing new code — skipping exploration leads to rewrites. But keep exploration focused: know what question each file read is answering. Once you have enough context to start, start. If a session includes both exploration and implementation, try to ship at least one concrete deliverable before the session ends.
- **Never push directly to main** — always create a PR
- **Run `bd sync` before pushing** to keep beads backlog in sync
- **Reference beads issue IDs** in commit messages (e.g., `feat: add camera [roots-of-reason-317.1]`)
- **Run `./tools/ror lint` before committing** — CI enforces zero warnings
- **Sign off commits** with `git commit -s`
- **Every PR body MUST include explicit `Closes` lines** for each bead it completes — one per line, using the full ID. Example:
  ```
  Closes roots-of-reason-fk5.3
  Closes roots-of-reason-fk5.4
  ```
  Do NOT just mention bead IDs informally in the summary — the `Closes` keyword is what triggers closure tracking. If a PR partially addresses a bead but doesn't complete it, use `Progresses roots-of-reason-XXX` instead.
- **Before merging a PR:** Verify every `Closes` line maps to a real open bead. After merge, run `bd close` for each.

## Standard Feature Ship Cycle

After implementing a feature, execute this sequence without interruption:

1. Create a worktree from latest main: `git fetch origin main && git worktree add .claude/worktrees/<branch> -b <branch> origin/main`
2. Work in the worktree directory
3. Run all tests (`./tools/ror test`) and fix failures
4. Run linter/formatter (`./tools/ror lint`) and fix issues
5. Commit with conventional message referencing bead ID (`git commit -s`)
6. Push branch and create PR with `Closes` lines (pre-push hook will rebase on main automatically)
7. Wait for CI — fix any failures
8. Merge to main (`gh pr merge --squash --delete-branch`)
9. Close related beads (`bd close <id>`)
10. Clean up: `git worktree remove .claude/worktrees/<branch> && git fetch --prune`

When a session includes multiple tasks, **complete the first task fully through merge** before starting the next. One merged feature is better than two half-done features.

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
