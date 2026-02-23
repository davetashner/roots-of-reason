# /adr — Create or Update Architecture Decision Record

Interactive ADR creation flow.

## Input

$ARGUMENTS — topic for the ADR (e.g., "error handling strategy") or existing ADR number to update (e.g., "ADR-012")

## Instructions

1. If $ARGUMENTS references an existing ADR number, read AGENTS.md and find that ADR to update it. Otherwise create a new one.

2. Read AGENTS.md to find the current ADR section and determine the next ADR number.

3. Ask the user clarifying questions about the decision: context, options considered, chosen approach, and consequences.

4. Generate the ADR in the project's established format (match the style in AGENTS.md):
   - **Number and Title** (e.g., ADR-012: Error Handling Conventions)
   - **Status**: Accepted
   - **Context**: Why this decision is needed
   - **Decision**: What was decided
   - **Consequences**: Trade-offs and implications

5. Append the new ADR to the ADR section in AGENTS.md (or update the existing one in place).

6. Create a beads decision issue: `bd create --type decision "<ADR title>"` and close it immediately with `bd close <id> --reason "Documented in AGENTS.md"`.

7. Run `ror lint` to verify no formatting issues were introduced.

8. Report the ADR number and title.
