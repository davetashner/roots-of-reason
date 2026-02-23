# /sprint — Suggest Next Tasks from Backlog

Analyzes the beads backlog and suggests the next tasks to work on.

## Input

$ARGUMENTS — optional: number of tasks to suggest (default: 5), or a focus area (e.g., "gameplay", "tools", "ui")

## Instructions

1. **Gather backlog state** by running these commands:
   - `bd ready -n 30` to get all unblocked, available issues
   - `bd list --status in_progress` to see what's currently being worked on
   - `bd orphans` to surface stale blockers or issues that may need attention
   - `bd blocked` to show blocked issues and their dependencies

2. **Parse $ARGUMENTS**:
   - If it's a number, use it as the count of tasks to suggest
   - If it's a string (e.g., "gameplay", "tools", "ui", "combat"), use it as a focus area filter
   - If it contains both (e.g., "3 gameplay"), parse accordingly
   - If empty, default to 5 suggestions with no filter

3. **Analyze and rank** the available issues considering:
   - **Priority**: P0 issues first, then P1, then P2. Never suggest P2 work when P0 items are available.
   - **Epic progress**: Prefer tasks that would complete or significantly advance an epic. Check parent epics and their completion percentage.
   - **Dependencies**: Prefer tasks that unblock the most downstream work. A task that unblocks 3 others is more valuable than one that unblocks none.
   - **Context**: If there's current in-progress work, suggest related tasks that maintain developer momentum and reduce context switching.

4. If $ARGUMENTS specifies a **focus area**, filter suggestions to issues matching that domain in their title, description, or epic name.

5. **Present the top suggestions** in a table:

   | # | Issue ID | Title | Priority | Epic | Unblocks | Why Now |
   |---|----------|-------|----------|------|----------|---------|
   | 1 | ... | ... | P0 | Epic Name (75%) | 3 tasks | Completes the epic |
   | 2 | ... | ... | P1 | Epic Name (50%) | 1 task | Related to in-progress work |

   For each suggestion, the "Why Now" column should give a brief, actionable reason.

6. If there are **orphaned or stale items**, mention them separately below the table with a recommendation (close, re-prioritize, or unblock).

7. **Ask the user** which task(s) they'd like to pick up. When they choose, offer to run `bd update <id> --status in_progress` to claim the work.
