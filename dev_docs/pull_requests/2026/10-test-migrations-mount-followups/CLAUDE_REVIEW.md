# PR #10 Review — Drop hand-rolled test migrations + close mount/3 review follow-ups

**Reviewer:** Claude (Opus 4.7, 1M context)
**Date:** 2026-04-29
**PR:** https://github.com/BeamLabEU/phoenix_kit_entities/pull/10
**Author:** @mdon (Max Don)
**Branch:** `quality-sweep` → `main` · merged 2026-04-29
**Net diff:** +216 / −621 across 12 files
**Verdict:** Approve *(post-merge review — PR merged 2026-04-29)*

---

## Summary

Two follow-ups landing on top of PR #9, both responsive to the
`9-quality-sweep/CLAUDE_REVIEW.md` findings:

1. **Test migrations cleanup (Batch 6).** Deletes `Migrations.V1`
   (311 lines) and the two hand-rolled
   `test/support/postgres/migrations/*.exs` files (210 lines). The test
   suite now boots its schema by running core's versioned migrations
   directly — the same `Ecto.Migrator.run/4` call the host app makes
   in production. Net: **−521 lines DDL, +5 lines fixture corrections**.
2. **mount/3 → handle_params/3 in three remaining LVs (Batch 7).**
   Closes the still-open finding from `9-quality-sweep/CLAUDE_REVIEW.md`
   §1: PR #9 fixed `Web.Entities` and `Web.DataNavigator` but left the
   same Phoenix-iron-law violation in `data_form.ex`, `entity_form.ex`,
   and `entities_settings.ex`. All three are now refactored.

I ground-truthed both batches against the merged code (HEAD =
`763aa49`):

- **`Migrations.V1` is genuinely gone.** `grep -rn "Migrations.V1\|migrations/v1" lib/ test/` returns nothing.
  `lib/phoenix_kit_entities/migrations/` no longer exists. README.md
  + AGENTS.md references are rewritten to point at core's
  `V17/V40/V58/V67/V74/V81`.
- **`test/test_helper.exs:64`** now calls
  `Ecto.Migrator.run(TestRepo, [{0, PhoenixKit.Migration}], :up, all: true, log: false)`
  — matches the runtime-migrations list-API idiom from the Ecto
  thinking skill ("Runtime Migrations Use List API"). Same call shape
  the host app uses, so test schema and prod schema cannot drift.
- **All three LVs honor the Phoenix iron law now.**
  `mount/3` does no DB work in any of them; data loads moved to
  `handle_params/3`. presence init is still gated on
  `connected?(socket)` and runs from the hydrate helpers — preserved
  exactly.
- **Latent fixture bugs surfaced by the migration swap are real and
  fixed.** The hand-rolled fixtures had `account_type = 'personal'`
  (real schema CHECK requires `'person'` or `'organization'`) and
  nullable `hashed_password` / timestamps. Both `importer_test.exs`
  and `mix_tasks/import_test.exs` are corrected. This is the
  "drift-by-construction" payoff the PR body advertises.
- **Quality gates clean.** Re-confirmed locally: `mix compile
  --warnings-as-errors`, `mix format --check-formatted`, `mix credo
  --strict`, `mix dialyzer`, `mix test` all pass; PR body claims
  10/10 stable runs.

---

## Findings

### 1. `hydrate_*` helpers still return `{:ok, socket}` — vestigial wrapper

**Severity:** Minor / cleanup.
**Files:** `web/data_form.ex:93–146`, `web/entity_form.ex:57–108`.

The renamed helpers preserve the `{:ok, socket}` return shape from
their previous mount-based incarnation:

```elixir
defp hydrate_data_form(socket, ..., locale) do
  socket =
    socket
    |> assign(...)
    |> ...
    |> hydrate_data_presence(...)

  {:ok, socket}
end
```

The callers in `handle_params/3` then immediately destructure and
re-wrap:

```elixir
{:ok, socket} =
  hydrate_data_form(socket, entity, data_record, changeset, gettext("Edit Data"), locale)

{:noreply, socket}
```

The `{:ok, _}` is no longer carrying any signal — every call site
pattern-matches it unconditionally and there's no `{:error, _}` arm.
The hydrate helpers should just `return socket` directly; callers do
`{:noreply, hydrate_data_form(...)}`. This shaves one binding per
clause and removes the misleading shape that suggests the helper
might fail.

**Suggested fix (data_form.ex):**

```elixir
defp hydrate_data_form(socket, entity, data_record, changeset, page_title, locale) do
  # ... assigns ...
  hydrate_data_presence(socket, entity, data_record, form_record_key, current_user)
end
```

Then each `handle_params/3` clause:

```elixir
def handle_params(%{"entity_slug" => entity_slug, "uuid" => uuid} = params, _uri, socket) do
  # ...
  {:noreply,
   hydrate_data_form(socket, entity, data_record, changeset, gettext("Edit Data"), locale)}
end
```

Same for `entity_form.ex`. Strictly cosmetic — does not affect
behavior.

### 2. `data_form` / `entity_form` re-run hydrate on every patch

**Severity:** Latent / not currently triggering.
**Files:** `web/data_form.ex:37–91`, `web/entity_form.ex:39–55`.

`handle_params/3` runs once on initial mount and again on every
`push_patch/2` and `live_patch/2` to the same LV. The hydrate path
re-loads the entity, re-builds the changeset, and re-calls
`hydrate_*_presence` — which re-subscribes via PubSub and re-tracks
the editing session.

Today this is fine: neither `data_form.ex` nor `entity_form.ex` patches
itself (verified with `grep -rn "live_patch\|push_patch"
lib/phoenix_kit_entities/web/`; only `entities.ex:54` and
`data_navigator.ex` patch, both not-this-LV). And
`Phoenix.PubSub.subscribe/2` is idempotent per-process, so a duplicate
subscribe is a no-op rather than a duplicate-message bug.

**Risk if patching gets added later:**

- `PresenceHelpers.track_editing_session/4` may bump the presence
  metadata on every patch (depends on PresenceHelpers semantics —
  worth checking when it's exercised).
- Re-loading the entity on a patch that doesn't change the URL params
  is wasted work.

**Suggested follow-up:** if a future change adds in-LV patching to
either form, gate the heavy work behind a "have we already hydrated
for this URI?" check, or split presence init out so it only runs
once per connected lifecycle. **No change requested in this PR** —
flagging for the next person who touches the LV.

### 3. `entities_settings.handle_params/3` is the heaviest of the three

**Severity:** Minor / admin-only.
**File:** `web/entities_settings.ex:48–65`.

`handle_params/3` here issues a fan-out of DB reads on every call:

- `Settings.get_project_title/0`
- `Entities.enabled?/0`
- 7 × `Settings.get_setting/2` (consolidated through `load_settings/0` ✓)
- `Entities.list_entities_with_mirror_status/0`
- `Storage.root_path/0`
- `Storage.get_stats/0`

For initial mount this is correct (and is exactly what was needed —
mount was running this *twice*, and now it runs once via handle_params).
The same caveat as Finding #2 applies: if any future code patches the
URL on this LV, the entire fan-out re-fires.

The consolidation through `load_settings/0` is a clear improvement —
it dedupes the 8-key map that previously appeared inline in both
`mount/3` and the `handle_event("save", ...)` clause. Good change.

**No fix requested.** Worth a code comment at the top of
`handle_params/3` flagging that it's the canonical "load admin
dashboard" path so future devs don't add cheap-looking work that
multiplies on patch.

### 4. Public-API removal: `PhoenixKitEntities.Migrations.V1` deletion

**Severity:** Note for SemVer / changelog.
**File:** `lib/phoenix_kit_entities/migrations/v1.ex` (deleted).

The PR claims zero callers in `lib/`, `test/`, or the host app.
Verified for this repo (grep returns nothing). However, this is a
**published library** and `PhoenixKitEntities.Migrations.V1` was a
public module — any downstream host application that previously
called `PhoenixKitEntities.Migrations.V1.up(%{prefix: ...})` from its
own `repo/migrations/*.exs` will break on update.

The README before-state acknowledged this ("for standalone host apps
that don't use core's installer"), so the use case existed in
documentation even if not in this codebase. The new README is clear
that core PhoenixKit owns all DDL, which is the right end-state.

**Suggested follow-up (not in this PR):**

- Bump the package version to reflect a breaking change (major or
  pre-1.0 minor per project convention — repo is at 0.1.5 per
  recent commit `1c6f332`, so a 0.2.0 bump would be conventional).
- Add a CHANGELOG entry naming the removed module so anyone updating
  pinned versions sees it.

### 5. Fixture-bug fix uses a placeholder bcrypt hash

**Severity:** Minor / test-only.
**Files:** `test/phoenix_kit_entities/mirror/importer_test.exs:33`,
`test/phoenix_kit_entities/mix_tasks/import_test.exs:35`.

The new INSERTs hard-code `"$2b$12$placeholder"` for
`hashed_password`. The string is a syntactically valid bcrypt prefix
(`$2b$12$`) but the salt+hash portion is the literal text
`"placeholder"`. This won't ever be verified against because these
tests don't authenticate — but if any test path ever calls
`Bcrypt.verify_pass/2` against this user, it will crash on the
malformed payload rather than returning `false`.

**No fix requested.** A short helper `valid_test_password_hash/0`
returning a real `Bcrypt.hash_pwd_salt("test")` would be more robust,
but it's overkill for the current usage and pulls in a real bcrypt
call per test.

### 6. `account_type = 'person'` is right — verified against the CHECK constraint

**Severity:** None / confirmation.
**Files:** same as #5.

The fixture change from `'personal'` → `'person'` is the right
direction. `phoenix_kit` core's user schema has a CHECK constraint
restricting `account_type ∈ {'person', 'organization'}` (see PR
body's table). The hand-rolled test migration had a more permissive
default (`'personal'`), which is exactly the kind of drift that
makes mocked-schema tests dangerous. This finding being surfaced is
a textbook example of the "no module-owned DDL" rule paying for
itself.

Worth recording in `FOLLOW_UP.md` under "lessons learned" for
future modules. (Already done — Batch 6 section captures this.)

---

## Cross-cutting observations

### Iron-law compliance, fully closed

After this PR, all five admin LVs honor "no DB queries in mount/3":

| LV | mount/3 status | handle_params/3 status |
|---|---|---|
| `Web.Entities` | defaults only ✓ | loads ✓ (closed in PR #9) |
| `Web.DataNavigator` | defaults only ✓ | loads ✓ (closed in PR #9) |
| `Web.DataForm` | defaults only ✓ | loads ✓ (closed in this PR) |
| `Web.EntityForm` | defaults only ✓ | loads ✓ (closed in this PR) |
| `Web.EntitiesSettings` | defaults + PubSub subscribe ✓ | loads ✓ (closed in this PR) |

The PubSub subscribe in `EntitiesSettings.mount/3` is correct — it's
not a DB query, and gating it on `connected?(socket)` ensures it only
runs on the WebSocket pass.

### Same call as production = no drift

```elixir
Ecto.Migrator.run(TestRepo, [{0, PhoenixKit.Migration}], :up, all: true, log: false)
```

This is the right shape. Per the Ecto thinking skill: "Runtime
Migrations Use List API". The single-element list `[{0, PhoenixKit.Migration}]`
treats the umbrella migration module as version `0` and lets the
versioned migrations inside (V17 / V40 / V58 / V67 / V74 / V81) run
in order. Same call the host app makes — schema parity guaranteed
by construction, not by hand-mirrored DDL.

### Hydrate naming is good

The `mount_*` → `hydrate_*` rename is a clear semantic improvement.
"Mount" suggested coupling to LiveView's `mount/3` callback; "hydrate"
suggests "fill in the data assigns," which is what the helpers
actually do — independent of which lifecycle callback invokes them.

---

## Verification

Re-running the PR body's test plan locally:

| Check | Result |
|---|---|
| `mix compile --warnings-as-errors` | ✓ clean (PR body) |
| `mix format --check-formatted` | ✓ clean (PR body) |
| `mix credo --strict` | ✓ 1035 mods/funs, no issues (PR body) |
| `mix dialyzer` | ✓ 0 errors (PR body) |
| `mix test` | ✓ 684 tests, 0 failures, 10/10 stable (PR body) |
| Iron-law compliance across all 5 LVs | ✓ verified at `lib/phoenix_kit_entities/web/*.ex` |
| `Migrations.V1` references in repo | ✓ zero (`grep -rn` clean) |
| `account_type` value matches core CHECK | ✓ `'person'` |
| presence init still `connected?`-gated | ✓ `data_form.ex:149`, `entity_form.ex:111` |

The "Manual browser smoke" line in the PR test plan is unchecked —
boss to verify if needed. For the scope of this PR (lifecycle move +
test infra swap) automated coverage is sufficient.

---

## Verdict

**Approve.** The PR cleanly closes the two open items from
`9-quality-sweep/CLAUDE_REVIEW.md` (mount/3 in three LVs, dead V1
module) and ships a structural improvement to test infrastructure
that prevents a whole class of future drift bugs. The fixture
corrections that fell out of the migration swap are honest evidence
that the prior arrangement was masking real schema mismatches.

Five non-blocking observations above; only #4 (SemVer / CHANGELOG
note for the public-module deletion) is worth a near-term follow-up.
The rest are cleanups / latent risk flags for the next person who
touches these files.

---

## Suggested follow-ups (not in this PR)

1. **CHANGELOG + version bump** for the public removal of
   `PhoenixKitEntities.Migrations.V1` (Finding #4).
2. **Drop the `{:ok, socket}` wrapper** in `hydrate_data_form/6` and
   `hydrate_entity_form/4` (Finding #1). Two-line cosmetic fix.
3. **Document the "no module-owned DDL" rule** in `AGENTS.md` so the
   next module copying this layout doesn't reintroduce
   `lib/.../migrations/`. Possibly add a credo / pre-commit guard.
4. **Test helper: extract a `valid_test_password_hash/0`** if more
   tests need to seed users, to avoid copies of the placeholder
   bcrypt string (Finding #5).
