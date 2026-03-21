# Release

End-to-end release workflow: analyze changes, update docs + version, verify, PR, merge, tag.
Run this on main after feature PRs are merged.

## Input

$ARGUMENTS — version number (e.g., `0.2.0`) or semver bump type (`major`, `minor`, `patch`).
If omitted, suggest version based on changes since last tag.

## Steps

### 1. Pre-checks

```bash
git checkout main && git pull
```

Verify clean working tree (no uncommitted changes).

### 2. Analyze changes since last release

```bash
# Find last version tag
git describe --tags --abbrev=0

# All commits since last tag
git log --oneline <last-tag>..HEAD

# All changed files since last tag
git diff --stat <last-tag>..HEAD
```

Categorize:
- Features (feat:)
- Fixes (fix:)
- Docs (docs:)
- Refactors (refactor:)
- Chores (chore:)

Determine version bump if not specified:
- Breaking change → major
- New feature → minor
- Bug fix / docs / chore → patch

### 3. Documentation gate

Check ALL of these before creating release branch:

**CHANGELOG.md:**
- Add new version section with today's date
- List all changes categorized by Added/Changed/Fixed/Removed
- Write user-facing descriptions (not just commit text)

**README.md:**
- Installation version matches new release?
- Any new features from this release missing from README?
- Environment variable table up to date?
- Examples still accurate?
- Build instructions still correct?

**mix.exs:**
- `@version` updated to new version

If any docs need updating, make ALL changes in this step.

### 4. Code verification

Run all checks. ALL must pass:

```bash
mix compile --warnings-as-errors
mix format --check-formatted
mix test    # if test/ directory exists
```

### 5. Release branch + PR

```bash
git checkout -b release/v<version>
git add mix.exs CHANGELOG.md README.md <any other changed docs>
git commit -m "release: v<version>"
git push -u origin release/v<version>
gh pr create --title "release: v<version>" --body "..."
```

PR body format:
```
## Summary
- Bump version to <version>
- Update CHANGELOG.md

### What's new in v<version>
<bullet points from CHANGELOG>

## Post-merge
git checkout main && git pull
git tag v<version>
git push --tags

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### 6. CI + Merge

```bash
# Wait for CI to pass
gh pr checks <pr-number> --watch

# Merge the release PR
gh pr merge <pr-number> --merge
```

### 7. Tag and push

```bash
git checkout main && git pull
git tag v<version>
git push --tags
```

This triggers the GitHub Actions release workflow which builds
standalone binaries for macOS ARM and Intel.

### 8. Verify release

```bash
# Wait for release CI to complete
gh run list --workflow="Build & Release" --limit 1

# Verify release was created with binaries
gh release view v<version>
```

### 9. Report

Show the user:
- Release version
- Release URL on GitHub
- CHANGELOG entry
- CI build status
