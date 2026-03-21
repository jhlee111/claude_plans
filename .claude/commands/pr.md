# Create PR

End-to-end workflow: verify code, check docs, commit, push, create PR.
Run this after implementation is done and tests pass locally.

## Input

$ARGUMENTS — short description of changes (used for branch name and PR title)

## Steps

### 1. Code verification

Run all checks in parallel. ALL must pass before proceeding:

```bash
mix compile --warnings-as-errors
mix format --check-formatted
mix test    # if test/ directory exists
```

If any fail, fix the issue and re-run. Do not skip.

### 2. Analyze changes

Run `git diff HEAD` and `git status` to understand what changed.
Categorize changes:
- New modules or features added?
- Public API changed?
- Config/dependency changes?
- UI changes?

### 3. Documentation gate

Based on the change analysis, check EACH of these:

**README.md:**
- New feature → needs section or mention?
- New environment variable → CLI Options table needs update?
- Changed behavior → examples still correct?
- Version in Installation section current?

**CHANGELOG.md:**
- NOT updated here. CHANGELOG is updated during `/release` only.

If docs need updating, make the changes now before committing.

### 4. Branch, commit, push

```bash
# Determine branch type from changes
# Types: feat/, fix/, docs/, refactor/, test/, chore/
git checkout -b <type>/<short-description>

# Stage relevant files (never git add -A)
git add <specific files>

# Commit with conventional format
git commit -m "<type>: <description>"
git push -u origin <branch>
```

### 5. Create PR

```bash
gh pr create --title "<type>: <description>" --body "..."
```

PR body format:
```
## Summary
<bullet points of what changed and why>

## Test plan
<checklist of what was tested>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### 6. Report

Show the user:
- PR URL
- Summary of what was included
- Any doc changes that were made
