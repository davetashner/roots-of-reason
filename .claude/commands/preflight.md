# /preflight — Pre-merge Quality Check

Runs all quality gates before merging a PR.

## Input

$ARGUMENTS — optional PR number or branch name. If empty, uses current branch.

## Instructions

1. **Identify the current branch** and any associated PR. If $ARGUMENTS is provided, use it as the PR number or branch name. Otherwise, detect the current branch with `git branch --show-current` and look up any open PR with `gh pr view`.

2. **Run the following checks in order**, reporting pass/fail for each:

   a. **Lint**: Run `tools/ror lint` — must pass with zero warnings.

   b. **Tests**: Run `tools/ror test` — all tests must pass.

   c. **Coverage**: Run `tools/ror coverage` — must meet the project threshold.

   d. **CI Status**: If there's an associated PR, check `gh pr checks` — all checks must pass. If no PR exists, skip this check and note it.

   e. **Beads Linkage**: Examine all commits on the branch (compared to `main`) with `git log main..HEAD --oneline`. Verify each commit message references a beads issue ID matching the pattern `[roots-of-reason-xxx]`. Flag any commits missing this reference.

   f. **No Secrets**: Scan staged and committed files for potential secrets. Look for:
      - `.env` files that should not be committed
      - Files containing strings like `secret`, `token`, `password`, `api_key`, `API_KEY`, `SECRET_KEY`, `PRIVATE_KEY`
      - Use `git diff main..HEAD` to check only the changes introduced by this branch

   g. **Signoff**: Verify all commits on the branch have `Signed-off-by:` lines. Check with `git log main..HEAD --format='%H %s' | while read hash msg; do git log -1 --format='%b' $hash; done` and confirm each contains a `Signed-off-by:` trailer.

3. **Present a summary table** with pass/fail status for each check:

   | Check | Status | Details |
   |-------|--------|---------|
   | Lint | PASS/FAIL | ... |
   | Tests | PASS/FAIL | ... |
   | Coverage | PASS/FAIL | ... |
   | CI Status | PASS/FAIL/SKIP | ... |
   | Beads Linkage | PASS/FAIL | ... |
   | No Secrets | PASS/FAIL | ... |
   | Signoff | PASS/FAIL | ... |

4. If **all checks pass**, report "Ready to merge" with confidence.

5. If **any checks fail**, list each failure with specific remediation steps. For example:
   - Missing signoff: suggest `git rebase --signoff main`
   - Missing beads linkage: suggest amending the commit message
   - Lint errors: show the specific warnings to fix
   - Secret detected: identify the file and line
