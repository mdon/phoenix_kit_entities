---
name: PR #14 review — test_helper migration call swap to ensure_current/2
description: Post-merge code review of PR #14 against ecto-thinking checklists. Single-file change to test/test_helper.exs.
type: project
---

# PR #14 Review — Swap `test_helper` to `PhoenixKit.Migration.ensure_current/2`

**Reviewer:** Claude (Opus 4.7, 1M context)
**Date:** 2026-05-05
**PR:** https://github.com/BeamLabEU/phoenix_kit_entities/pull/14
**Companion:** https://github.com/BeamLabEU/phoenix_kit/pull/515 (core API)
**Author:** @mdon (Max Don)
**Branch:** `migration-cleanup` → `main` · merged 2026-05-05
**Net diff:** +9 / −1 across 1 file (`test/test_helper.exs`)
**Skills consulted:** `elixir:using-elixir-skills`, `elixir:ecto-thinking`
**Verdict:** Approve · two non-blocking nits *(post-merge review — PR already merged; both nits resolved as a follow-up in this same review pass — see "Follow-up applied" below)*

---

## Summary

One-line behavioural fix to the test-suite boot path. The previous call

```elixir
Ecto.Migrator.run(TestRepo, [{0, PhoenixKit.Migration}], :up, all: true, log: false)
```

is idempotent at the *outer* `Ecto.Migrator` layer in a way that defeats
its inner purpose: after the first invocation, `schema_migrations`
records "version 0 applied", and on every subsequent run Ecto filters
`{0, PhoenixKit.Migration}` out of the pending list before the inner
runner is even consulted. PhoenixKit's own `up/1` short-circuit (the
table-comment marker) never gets a chance to evaluate — so any `Vxxx`
migration that ships in a core upgrade silently never applies to the
test database, and the test schema drifts from production. New tables
or columns from `V90+` would 500 mid-suite the moment a context tries
to query them, with no obvious link to the boot-time migrate call.

The fix swaps to `PhoenixKit.Migration.ensure_current/2` (core
1.7.105+, ships in phoenix_kit#515), which calls `Ecto.Migrator.up/4`
with a fresh `:os.system_time(:microsecond)` version on each call.
Ecto sees a "new" migration, invokes the inner `PhoenixKit.Migration.Runner`,
which re-enters `PhoenixKit.Migration.up/1` — and *that* layer is
properly idempotent via PhoenixKit's own marker. Net: stale migrations
get applied; clean databases short-circuit cheaply.

I read the merged diff against `main` (`e6a86db..0f1d753`), audited the
upstream `ensure_current/2` source at `/workspace/phoenix_kit/lib/phoenix_kit/migration.ex:188-259`,
and checked the rest of the entities tree for any other call sites
using the deprecated pattern (`grep` confirms `test_helper.exs` was
the only one).

---

## What's right

- **The diagnosis is correct and non-obvious.** The
  `Ecto.Migrator.run([{0, M}], :up, all: true)` shape is widely copied
  from older PhoenixKit/Oban-style READMEs precisely because it *looks*
  re-runnable. The staleness only surfaces when a downstream-only repo
  (entities) lags a core release — exactly the scenario this workspace
  has been hitting since V40/V58/V67/V74/V81 evolved the entity tables.
  The PR description and inline comment both name the root cause
  precisely.
- **Microsecond resolution is the right precision floor.** Millisecond
  would still leave a collision window during fast suite restarts;
  microsecond reduces it 1000× and stays bigint-safe through ~2262.
  The upstream docstring (`migration.ex:245-250`) calls this out
  explicitly, and the choice survives clock-skew under normal NTP
  behavior — only a backwards step of microseconds at exactly the wrong
  moment could hide a shipped migration.
- **`PhoenixKit.Migration.Runner` is module-scoped, not a defmodule-per-call
  closure.** That matters because `Ecto.Migrator.up/4` resolves `up/0`
  / `down/0` against a known module name; an anonymous module would
  fail to register. The upstream design at `migration.ex:271-305`
  shows `Runner` was deliberately split out for this reason and to
  forward `:prefix` correctly via `runner_opts/1` — `nil` prefix
  doesn't get threaded through (which would otherwise crash inside
  `String.replace/4` when `with_defaults/2` tries to override the
  `"public"` default). Entities doesn't pass a prefix here, but the
  upstream API survives multi-tenant call sites cleanly.
- **The inline comment is accurate and load-bearing.** Names the
  staleness story, the version requirement, the companion PR, and
  points readers at `dev_docs/migration_cleanup.md` for the full
  write-up. A future contributor scanning this file will not be
  tempted to "simplify" back to `Ecto.Migrator.run`.
- **No collateral damage.** `grep` across `lib/` and `test/` confirms
  this was the only deprecated call site in the entities repo. No
  schemas, no contexts, no other helpers were touched.
- **Failure semantics preserved.** `ensure_current/2` raises on
  advisory-lock contention or migration crash (it does not wrap in
  `{:error, _}`), and the surrounding `try/rescue/catch` in
  `test_helper.exs:83-101` already handles raises and `:exit` —
  switching from the old call to the new one doesn't change the
  observable boot-failure behavior.
- **`Ecto.Adapters.SQL.Sandbox.mode/2` and the `Code.require_file`
  block both still execute after the migrate call returns.** Order
  preserved; sandbox manual-mode is established before any
  `DataCase.setup/1` opens checkouts. No race introduced.

---

## Findings

Numbered N-prefix, severity tagged. Both are nits — neither blocks the
merge.

### N1 · Broken doc reference: `dev_docs/migration_cleanup.md` doesn't exist in this repo · NIT

The comment ends with:

```
…—  see `dev_docs/migration_cleanup.md` for the staleness story.
```

`find /workspace/phoenix_kit_entities -name "migration_cleanup*"`
returns nothing. `find /workspace/phoenix_kit -name "migration_cleanup*"`
also returns nothing. The doc presumably lives in the
`phoenix_kit` core repo *under a different name* (or hasn't been
written yet — phoenix_kit#515 may carry it as part of the same change),
but a contributor sitting in the entities repo opening this comment
will look for the file locally, not find it, and have to guess.

**Recommendation:** Either qualify the path (`see
phoenix_kit#515 / dev_docs/migration_cleanup.md in the core repo`),
or replace with a one-line summary embedded in the comment (the
docstring on `ensure_current/2` upstream at `migration.ex:188-241`
is already the canonical write-up — reference *it* by module/function
name instead of a separate doc).

### N2 · Lockfile still pins `phoenix_kit 1.7.103`; `~> 1.7` resolves to a version where this function does not exist · LOW

```
# mix.lock
"phoenix_kit": {:hex, :phoenix_kit, "1.7.103", …}

# mix.exs
{:phoenix_kit, "~> 1.7"}
```

`PhoenixKit.Migration.ensure_current/2` ships in 1.7.105+. Until core
publishes that release, `mix deps.get && mix test` against the hex
version will fail with `UndefinedFunctionError` at boot — exactly the
"CI red until 1.7.105 publishes" outcome the PR description acknowledges.

The PR description handles this consciously, so I'm flagging not as a
defect but as a follow-up tracker: once 1.7.105 lands on hex,
`mix.lock` needs a refresh, and ideally `mix.exs` should bump the
floor to `~> 1.7 and >= 1.7.105` so a fresh `mix deps.get` for a
contributor on a clean checkout doesn't silently downgrade. (The
existing `~> 1.7` admits 1.7.0 through 1.99.x, which is permissive
enough to mask the issue.)

**Recommendation:** Once core 1.7.105 publishes, follow up with
either (a) `mix deps.update phoenix_kit` plus a CI-greens commit,
or (b) the same plus `{:phoenix_kit, "~> 1.7", override: true}` /
explicit minor floor in `mix.exs` to prevent regressions on fresh
checkouts.

---

## Skill audit

- **`elixir:ecto-thinking`** — The "Runtime Migrations Use List API"
  gotcha (`Ecto.Migrator.run(repo, [{0, M1}, {1, M2}], :up, opts)`)
  is exactly the shape this PR moves *away from*. The skill's note is
  accurate at face value but doesn't surface the version-0 idempotency
  trap when the list is `[{0, _}]` and gets re-run across process
  boots — `ensure_current/2` is the better-documented escape hatch.
  Worth proposing an addition to the skill in a follow-up so other
  PhoenixKit-style libs avoid the same pitfall.
- **`elixir:using-elixir-skills`** — Routing was correct: this is an
  Ecto/migration concern, no LiveView/PubSub/OTP surface area, no
  changesets or query design. `ecto-thinking` was sufficient.
- **`elixir:phoenix-thinking`** / **`elixir:otp-thinking`** /
  **`elixir:oban-thinking`** — N/A. No LiveView, no processes, no
  background jobs.

---

## Stale-state / regression checklist

- `mix format --check-formatted` — single-file change, no formatting
  shifts visible in the diff.
- `mix credo --strict` — no new code paths.
- `mix compile --warnings-as-errors` — depends on local core
  availability; PR description verified via `phoenix_kit_parent`
  path-dep override against core 1.7.104+ (which carries the function
  ahead of its hex publish).
- `mix test` — 775/775 per PR description, 3 consecutive stable runs.
- The deprecated pattern is not used elsewhere in the repo (verified
  via `grep -rn "Ecto.Migrator.run" /workspace/phoenix_kit_entities/{lib,test}`
  → only the new call's *comment* mentions it).

I did not re-run the test suite from this review — local hex deps
resolve to 1.7.103, which lacks the function. Re-verification will
be possible after core 1.7.105 publishes (per N2).

---

## Verdict

Approve. Genuinely tightens a real bug — V40/V58/V67/V74/V81 silently
not re-applying to a long-lived test DB is exactly the class of
"works on my machine, breaks on rebuilds" that wastes triage cycles.
The fix is one line, the comment carries its own load, and the
upstream `ensure_current/2` has a thorough docstring covering the
edge cases (clock skew, schema_migrations row accumulation, prefix
forwarding).

Both findings are housekeeping: a doc reference that resolves
nowhere, and a lockfile that hasn't yet caught up with the function
it depends on. Neither needs a revert; both are addressable in
follow-up commits once core 1.7.105 publishes.

---

## Follow-up applied (2026-05-05)

Both findings were resolved in the same review pass; the changes are
shipped alongside this doc. Net diff: 2 files (`mix.lock`,
`test/test_helper.exs`) plus this review doc.

- **N1 — fixed.** `test/test_helper.exs:65-72` — the broken
  `dev_docs/migration_cleanup.md` pointer was replaced with a
  reference to the upstream `PhoenixKit.Migration.ensure_current/2`
  docstring (the canonical write-up — `migration.ex:188-241` in core).
  No new file created; the docstring already covers the staleness
  story, clock-skew window, schema_migrations row accumulation, and
  prefix forwarding.
- **N2 — fixed (partial).** `phoenix_kit 1.7.105` was confirmed
  published on hex (`mix hex.info phoenix_kit` → "Releases: 1.7.105,
  1.7.104, …"). Ran `mix deps.update phoenix_kit`, which advanced
  `mix.lock` from 1.7.103 → 1.7.105. `mix compile` clean against the
  new lockfile — `ensure_current/2` now resolves at runtime.
  - `mix.exs` constraint left at `~> 1.7` rather than tightened to
    `"~> 1.7", ">= 1.7.105"`. Decision: rely on the lockfile for
    pinning rather than encoding a floor in the manifest. Risk: a
    contributor running `mix deps.unlock --all && mix deps.get`
    could silently resolve to 1.7.103 again and hit
    `UndefinedFunctionError` at boot. Acceptable trade-off given
    the constraint shape preferred for this repo.
  - `mix test` not re-run from the review sandbox (no `psql` on
    PATH; `test_helper.exs:33` raises `ErlangError :enoent` on
    `System.cmd("psql", ...)` — pre-existing behavior, unrelated to
    PR #14). Verification by the merge-author still stands.

## Open follow-up

- **Skill addition** — Propose an `elixir:ecto-thinking` skill entry
  for the `Ecto.Migrator.run([{0, _}], :up, all: true)` re-runnability
  trap and the `ensure_current/2` pattern as the documented fix. Not
  in scope for this repo — needs to land in the skill plugin.
