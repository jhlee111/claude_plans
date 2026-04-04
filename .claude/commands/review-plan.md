# Review Plan

Review a Claude Code plan for Elixir/Phoenix best practices and flag anti-patterns.
Use this after writing or receiving a plan that involves Elixir, Phoenix, LiveView, or OTP code.

## Input

$ARGUMENTS — path to a plan file, or "current" to review the plan in the active conversation.
If omitted, review the most recently modified plan in `~/.claude/plans/`.

## Steps

### 1. Load the plan

If a path is given, read the file. If "current", use the plan from the current conversation.
If omitted:

```bash
ls -t ~/.claude/plans/ | head -1
```

Read the plan content. If the plan is empty or not an implementation plan, stop and tell the user.

### 2. Identify Elixir/Phoenix code sections

Scan the plan for:
- Module definitions, file paths (`.ex`, `.exs`, `.heex`)
- Code snippets, function signatures, data structures
- Architecture decisions (GenServers, supervisors, contexts, LiveViews)
- Database/Ecto schema changes
- Test strategies

If the plan has no Elixir/Phoenix content, tell the user and stop.

### 3. Review against best practices

Check EACH of the following categories. For each issue found, note the task/section where it occurs and explain what to change.

**Pattern Matching & Control Flow:**
- Conditional logic (`if`/`else`, `cond`) that should be pattern matching on function heads
- Nested `case` statements that should be refactored to `with` or separate functions
- Missing guard clauses where type/value checking is needed
- Using exceptions for control flow instead of `{:ok, _}` / `{:error, _}` tuples

**Data Structures:**
- Using raw maps where structs are appropriate (known, fixed shape)
- Appending to lists (`list ++ [new]`) instead of prepending (`[new | list]`)
- Using keyword lists where maps are better (or vice versa)
- Missing or incorrect typespec for public functions

**OTP & Processes:**
- GenServer with complex state that should be broken into multiple processes
- Missing supervision tree considerations (who supervises what, restart strategy)
- Using `cast` where `call` is needed for back-pressure
- Synchronous calls without timeout considerations
- Missing `handle_continue/2` for expensive post-init work
- Process dictionary usage (almost always wrong)
- Missing `Task.Supervisor` for spawned tasks

**Phoenix & LiveView:**
- Business logic in LiveView modules instead of context modules
- Fat `handle_event` callbacks that should delegate to contexts
- Missing `handle_info` for PubSub or process messages
- Not using `assign_async` or `start_async` for expensive operations
- Mounting expensive work in `mount/3` instead of deferring
- Missing dead view (`render/1`) vs connected view separation
- Raw SQL or Repo calls in LiveView/controller (should go through context)
- Component functions that should be stateless function components

**Ecto & Database:**
- N+1 query patterns (loading associations in a loop)
- Missing indexes for fields used in WHERE/ORDER BY
- Changesets without proper validations at the boundary
- Using `Repo.insert!` / `Repo.update!` where error tuples are better
- Schema changes without migration plan
- Missing foreign key constraints or unique indexes

**Testing:**
- Missing test coverage for key paths (happy path + error cases)
- Mocking internal modules instead of using dependency injection or behaviour callbacks
- Tests that depend on execution order
- Missing async: true for independent test modules
- Integration tests that should be unit tests (or vice versa)

**Security & Performance:**
- `String.to_atom/1` on user input
- Unbounded `Enum` operations on potentially large collections (prefer `Stream`)
- Missing rate limiting or pagination for user-facing endpoints
- Storing sensitive data in plaintext

### 4. Check architecture patterns

Review the overall structure:
- Does the plan follow Phoenix contexts (bounded contexts) for domain logic?
- Are responsibilities properly separated (web layer vs domain vs infrastructure)?
- Is there a clear data flow (request → router → controller/LiveView → context → schema)?
- Are side effects (email, external API calls) isolated and testable?
- For multi-step workflows, is `Ecto.Multi` or `with` used for transactional integrity?

### 5. Flag anti-patterns

Specifically call out if the plan contains any of these known anti-patterns:

| Anti-pattern | What to do instead |
|---|---|
| God LiveView (>500 lines) | Break into live components, extract helpers |
| Context-free Repo calls | Move data access into context modules |
| Implicit process coupling | Use PubSub or explicit message passing |
| Config at compile time | Use runtime config or Application.get_env |
| Blocking the caller | Use async patterns (Task, GenServer cast) |
| Catch-all handle_info | Add specific clauses, log unexpected messages |
| Hardcoded external URLs | Move to config/environment variables |
| Shared mutable state via ETS without clear ownership | Wrap ETS in a GenServer or use Agent |
| Using `apply/3` with user input | Whitelist allowed modules/functions |
| Deep module nesting | Flatten namespace, use aliases |

### 6. Produce review report

Output a structured review:

```
## Plan Review: <plan title>

### Summary
<1-2 sentence overall assessment>

### Issues Found

#### Critical (must fix before implementing)
- [ ] **[Task N]** <description> — <what to change>

#### Recommended (should fix)
- [ ] **[Task N]** <description> — <what to change>

#### Suggestions (nice to have)
- [ ] **[Task N]** <description> — <what to change>

### What looks good
<bullet points of things the plan does well>

### Checklist for implementation
- [ ] All context modules identified and created
- [ ] Supervision tree planned for any new processes
- [ ] Migrations planned with rollback strategy
- [ ] Test files and strategies identified
- [ ] No business logic in web layer
```

If using annotations, also add the findings as annotations to the plan file
using the annotation format: `<!-- A1 (## Section > paragraph): Review comment -->`
