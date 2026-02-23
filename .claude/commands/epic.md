# /epic — Plan and Create an Epic with Stories

Takes a feature description and breaks it into an epic with child stories.

## Input

$ARGUMENTS — feature description (e.g., "resource trading between players")

## Instructions

1. Analyze the feature described in $ARGUMENTS in the context of this project (Godot 4 civ RTS).

2. Read AGENTS.md and CLAUDE.md to understand the project architecture and conventions.

3. Break the feature into 5-12 discrete stories/tasks, each representing a single PR's worth of work.

4. For each story, identify:
   - Clear title (imperative form)
   - Description with acceptance criteria
   - Dependencies on other stories in this epic
   - Priority (P0 for foundational, P1 for core, P2 for polish)

5. Present the epic plan to the user for review before creating issues.

6. Once approved, create the beads epic and child issues:
   - `bd create --type epic "<Epic title>"`
   - `bd create --type task "<Story title>" --parent <epic-id>` for each story
   - Set up blocker relationships with `bd update <id> --blocked-by <dep-id>` where needed

7. Run `bd sync` after creating all issues.

8. Report the epic ID, number of stories, and the dependency graph.
