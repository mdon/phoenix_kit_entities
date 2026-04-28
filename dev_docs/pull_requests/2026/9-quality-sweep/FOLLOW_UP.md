# Follow-up Items for PR #9 (Quality sweep + re-validation)

The original sweep that opened this PR is documented in the workspace
`AGENTS.md` entry for `phoenix_kit_entities` (full Phase 1 + Phase 2 with
8 PR-followup commits, 6 quality commits, and 2 post-ship bug fixes for
the language-tab leak and the stale `:created_by` collab broadcast).

This document covers the **2026-04-28 re-validation pass** (third module
through the post-Apr re-validation pipeline after `ai`, `locations`,
`hello_world`, `sync`, `document_creator`, `publishing`).

## Re-validation context (2026-04-28)

Phase 1 PR triage re-verified clean — the existing FOLLOW_UPs for #4 / #5
/ #8 still hold; #1 / #2 / #3 pre-date the FOLLOW_UP format.

**C0 baseline:** 384 tests / 0 failures; one pre-existing typing-violation
warning (`assert tabs != []`) and ongoing `DBConnection.OwnershipError`
log spam from core's `Settings.get_boolean_setting/2` (lives upstream;
matches the AI module's pre-existing issue per workspace AGENTS.md).

Three C12 Explore agents ran in parallel against `lib/` + `test/` with the
named-category prompts from workspace AGENTS.md. Two HIGHs flagged by the
security agent were verified as false positives:
- "Auth context fns lack `actor_uuid` enforcement" — design intent; auth
  is at LV mount via `live_session :phoenix_kit_admin` on_mount hook
- "Mass assignment via `Map.keys(types)`" — `types` is a literal map
  defined inline (`entities_settings.ex:559-568`); semantically equivalent
  to a hardcoded allowlist

The remaining MEDIUM/LOW findings are split across Batch 2 and Batch 3.

## Fixed (Batch 2 — 2026-04-28 re-validation)

Structural pipeline deltas the original sweep predates (canonical `Batch 2`
shape from the workspace re-validation precedent):

- ~~**ActivityLog rescue missing canonical shape**~~ —
  `lib/phoenix_kit_entities/activity_log.ex` now matches the
  `Postgrex.Error -> :ok` / `DBConnection.OwnershipError -> :ok` /
  `error -> Logger.warning(...)` / `catch :exit, _ -> :ok` shape from
  workspace AGENTS.md:1947-1966 (publishing's Batch 5 trap). Previously
  the wrapper logged `Logger.warning` even for the expected
  sandbox-crossing exceptions, producing test-time noise.
- ~~**`handle_info` catch-alls silent across all 5 LVs**~~ — promoted to
  `Logger.debug(fn -> "#{LV}: unhandled handle_info — #{inspect(message)}" end)`
  per workspace AGENTS.md:885-887. Affects `data_navigator.ex`,
  `data_form.ex`, `entities_settings.ex`, `entities.ex`, `entity_form.ex`.
  Each LV gained `require Logger` at the module level.
- ~~**Field-type `description` raw English in `@field_types`**~~ —
  `lib/phoenix_kit_entities/field_types.ex:54-200`. 12 type descriptions
  wrapped via the literal-clause helper `description_for/1` (pattern from
  workspace AGENTS.md:846-848 — `gettext(label)` over a variable isn't
  extractable). `for_picker/0` now routes through the helper so its
  exposed `:description` is gettext-translated.
- ~~**`@spec` missing on `routes.ex` + `sitemap_source.ex`**~~ — added
  specs on `admin_locale_routes/0`, `admin_routes/0`, `generate/1`
  (routes.ex) and `source_name/0`, `sitemap_filename/0`, `sub_sitemaps/1`,
  `enabled?/0`, `collect/1` (sitemap_source.ex). 8 new specs total.

## Fixed (Batch 3 — fix-everything pass 2026-04-28)

Triggered by Max's "default scope is FIX EVERYTHING" — closes every
in-scope finding the security/cleanliness/i18n agents surfaced. Per
`feedback_quality_sweep_scope.md`'s explicit-override clause: SSRF /
spec backfill / component refactors all become in-scope when the user
authorises closure.

- ~~**`mirror/storage.ex` bare `rescue _ -> nil` clauses**~~ — narrowed
  to `e in [ArgumentError, RuntimeError, FunctionClauseError]` (and
  `[ArgumentError, RuntimeError]` for `parent_app_root/0`) with a
  `Logger.debug` fallback line so real bugs surface while the documented
  fallback paths (Path.expand on weird input, Application.app_dir before
  parent boots) still return `nil` cleanly.
- ~~**Pre-existing typing-violation warning**~~ —
  `test/phoenix_kit_entities_test.exs:94` switched from
  `assert tabs != []` to `refute Enum.empty?(tabs)` per Elixir 1.19
  type-checker (compares `[Tab.t()]` against `[]` was flagged as
  always-true / always-false on disjoint types). Pre-existing; cleared
  here so the warning doesn't mask future surprises.
- ~~**`mix.exs` missing `test_coverage [ignore_modules]` filter**~~ —
  added per workspace AGENTS.md:497-519 + document_creator Batch 5
  precedent. Filters `PhoenixKitEntities.Test.*` plus DataCase /
  LiveCase / ActivityLogAssertions so the percentage tracks production
  code, not test-support boilerplate.
- ~~**Missing base→dialect translation tests**~~ —
  `test/phoenix_kit_entities/entity_multilang_test.exs` gained two
  `describe` blocks (8 new tests): "dialect/base normalization" pins
  `es → es-ES`, `es-ES → es`, exact-match wins over collapse, and
  deterministic sort across multiple dialects of the same base;
  "edge cases on free-text fields" pins Unicode round-trip (Japanese),
  SQL-metacharacter literals, 4096-char strings, and emoji.
- ~~**Field-type description tests**~~ —
  `test/phoenix_kit_entities/field_types_test.exs` gained 3 new tests:
  `for_picker/0`'s description routes through `description_for/1`,
  every known type returns a non-empty translated string, and EXACT
  string assertions on each of 12 type descriptions (catches drift from
  the pattern AGENTS.md:846-848 forbids).
- ~~**ActivityLog rescue test**~~ — new
  `test/phoenix_kit_entities/activity_log_rescue_test.exs` (`async: false`)
  drops `phoenix_kit_activities` mid-transaction (sandbox rollback at
  test exit per workspace AGENTS.md:374-385) to exercise the
  `Postgrex.Error -> :ok` rescue branch and confirm no `Logger.warning`
  is emitted. Pins the canonical-rescue Batch 2 fix.
- ~~**Per-LV `handle_info` Logger.debug pinning tests**~~ — every LV
  smoke test (`data_navigator_live_test`, `data_form_live_test`,
  `entities_live_test`, `entities_settings_live_test`,
  `entity_form_live_test`) gained a "logs at :debug level" test that
  lifts `Logger.level` to `:debug` for the duration (the test config sets
  `:warning` globally, which filters debug *before* `capture_log` sees
  it), sends a stray message, and asserts the LV's catch-all label
  surfaces in the captured log. 5 new tests.
- ~~**`test/support/live_case.ex` `require Logger`**~~ — added so the
  per-LV pinning tests (which call `Logger.level` / `Logger.configure`)
  compile against the `Logger` module without each test having to
  re-require it.

## Reclassified as N/A on re-inspection

Findings the C12 agents flagged that turned out to be false positives.
Recorded here so the next re-validation pass doesn't re-flag them:

- **`data_navigator.ex:860` raw `<select name="status">`** — already
  inside a `<label class="select w-full">` daisyUI 5 wrapper one line
  above (`:868`). Sync-sweep precedent at workspace AGENTS.md:1693-1696:
  "raw select" looking at first glance is almost always inside the
  wrapper; check the parent `<label>` before flagging.
- **`@impl true` missing on subsequent `handle_event` clauses in
  `data_navigator.ex`** — Elixir's `@impl` applies per function (by
  name+arity), not per pattern-match clause. The first clause carries
  the annotation; subsequent clauses inherit it. `mix compile
  --warnings-as-errors` is clean.
- **`entities_settings.ex:574` `Map.keys(types)` cast pattern** — the
  `types` map is defined as a literal three lines above the cast call.
  `Map.keys(types)` is semantically equivalent to a hardcoded
  `[:entities_enabled, :auto_generate_slugs, ...]` allowlist. Stylistic
  preference at most; not a mass-assignment risk.

## Surfaced for Max — discovered during sweep, not closed in this batch

- **`lib/phoenix_kit_entities/web/data_view.ex` is unrouted dead code.**
  Not registered in `lib/phoenix_kit_entities/routes.ex`, no callers
  anywhere in this repo or in core `phoenix_kit`. Commit `cacc3d1`
  ("Remove misleading Data View override example and tighten routing
  docs") removed the override docs but kept the module. The C12 agent
  flagged it as "missing test file"; writing a test for code that's
  never executed is busywork. **Recommendation: delete the module +
  scrub `README.md:151`, `OVERVIEW.md:45`, `CHANGELOG.md:13,47`,
  `lib/phoenix_kit_entities/DEEP_DIVE.md:711`** unless it's intended
  as a downstream override target — in which case, register a test-only
  route + add a smoke test. Awaiting Max's call.

## Files touched

| File | Change | Batch |
|------|--------|-------|
| `lib/phoenix_kit_entities/activity_log.ex` | Canonical rescue shape (Postgrex.Error / DBConnection.OwnershipError / catch :exit) | 2 |
| `lib/phoenix_kit_entities/web/data_navigator.ex` | `require Logger`, handle_info Logger.debug catch-all | 2 |
| `lib/phoenix_kit_entities/web/data_form.ex` | `require Logger`, handle_info Logger.debug catch-all | 2 |
| `lib/phoenix_kit_entities/web/entities_settings.ex` | `require Logger`, handle_info Logger.debug catch-all | 2 |
| `lib/phoenix_kit_entities/web/entities.ex` | `require Logger`, handle_info Logger.debug catch-all | 2 |
| `lib/phoenix_kit_entities/web/entity_form.ex` | handle_info Logger.debug catch-all | 2 |
| `lib/phoenix_kit_entities/field_types.ex` | `description_for/1` literal-gettext helper, `for_picker/0` routes through it | 2 |
| `lib/phoenix_kit_entities/routes.ex` | `@spec` on 3 public functions | 2 |
| `lib/phoenix_kit_entities/sitemap_source.ex` | `@spec` on 5 callbacks | 2 |
| `lib/phoenix_kit_entities/mirror/storage.ex` | `require Logger`, narrowed rescues with Logger.debug fallback | 3 |
| `mix.exs` | `test_coverage: [ignore_modules: [...]]` filter | 3 |
| `test/phoenix_kit_entities_test.exs` | Pre-existing `assert tabs != []` typing-violation cleared | 3 |
| `test/phoenix_kit_entities/entity_multilang_test.exs` | +8 dialect/base + edge-case tests | 3 |
| `test/phoenix_kit_entities/field_types_test.exs` | +3 `description_for/1` + for_picker pinning tests | 3 |
| `test/phoenix_kit_entities/activity_log_rescue_test.exs` | New file — pins canonical rescue (DROP TABLE in sandbox) | 3 |
| `test/phoenix_kit_entities/web/data_navigator_live_test.exs` | +1 Logger.debug pinning test | 3 |
| `test/phoenix_kit_entities/web/data_form_live_test.exs` | +1 Logger.debug pinning test | 3 |
| `test/phoenix_kit_entities/web/entities_live_test.exs` | +2 (catch-all smoke + Logger.debug pin) | 3 |
| `test/phoenix_kit_entities/web/entities_settings_live_test.exs` | +2 (catch-all smoke + Logger.debug pin) | 3 |
| `test/phoenix_kit_entities/web/entity_form_live_test.exs` | +1 Logger.debug pinning test | 3 |
| `test/support/live_case.ex` | `require Logger` for per-LV Logger.level lift in pinning tests | 3 |

## Verification

- `mix format --check-formatted` ✓
- `mix compile --warnings-as-errors` ✓
- `mix credo --strict` ✓ (1045 mods/funs, no issues)
- `mix dialyzer` ✓ (0 errors)
- `mix test` ✓ (**405 tests, 0 failures**, up from 384 baseline = +21 net)
- 10× consecutive `mix test` runs all clean (10/10 stable)

Pre-existing log spam from core `Settings.get_boolean_setting/2` (returns
`DBConnection.OwnershipError` on sandbox-crossing) still present —
suppression lives upstream in core, not in this module's `enabled?/0`
which already has both `rescue _ -> false` and `catch :exit, _ -> false`.

## Fixed (Batch 4 — coverage push 2026-04-28)

`mix test --cover` push from the post-Batch-3 baseline of **31.39%** to
**67.33%** using only `mix test --cover` — no Mox / no excoveralls / no
Bypass / no external HTTP stubs. +240 tests (405 → 645), 5/5 stable.

### Production bug fixes surfaced by the controller test

Three real bugs found by writing the public-form controller's first
test. None had been previously test-covered; the success path crashed
on every submission in production.

- ~~`entity_form_controller.ex:243 + 342` `entity.id`~~ — primary key
  on the Entity schema is `:uuid` (UUIDv7 convention), not `:id`. Both
  call sites would have crashed with `KeyError` on every public-form
  submission. Fixed to `entity.uuid`.
- ~~`entity_form_controller.ex:299` `logger.warning(...)`~~ — variable-
  bound macro dispatch doesn't resolve to `Logger.warning/1`
  (macros aren't atom-callable). Affected: every `save_log` security
  flag path raised `UndefinedFunctionError`. Fixed to call
  `Logger.warning(...)` directly + dropped the unused `_logger`
  parameter.

### New test files

11 new test files covering the 0%-coverage modules and gap-filling for
the mid-tier modules:

- `mirror/storage_test.exs` (17 tests) — settings toggles, path
  resolution, write/read/delete round-trip, list_entities, get_stats.
- `mirror/exporter_test.exs` (12 tests) — serialize_entity,
  serialize_entity_data, export_entity (struct + name), export_*_data,
  export_all + with/without data mirroring branches.
- `mirror/importer_test.exs` (18 tests) — `:skip` / `:overwrite` /
  `:merge` strategies on definitions + data records, no-slug branch,
  preview_import, detect_conflicts, import_all, import_selected.
- `sitemap_source_test.exs` (11 tests) — every callback with auto-pattern
  toggles, metadata-exclude + draft-status filtering.
- `url_resolver_extras_test.exs` (24 tests) — gap-fills the existing
  `url_resolver_test.exs`.
- `entity_data_extras_test.exs` (39 tests) — list_*, get*, position
  helpers, search, filter_by_status, bulk_*, translation helpers,
  public_path/url/alternates.
- `context_extras_test.exs` (41 tests) — top-level PhoenixKitEntities
  module surface (stats, counts, callbacks, sort-mode, mirror
  settings, definition translations).
- `form_builder_render_test.exs` (20 tests) — build_field/3 per type
  + build_fields/3 + get_field_value/2.
- `activity_log_extras_test.exs` (4 tests) — log/1 happy path +
  with_log/2 :ok / :error branches.
- `controllers/entity_form_controller_test.exs` (20 tests) — every
  submit/2 branch (entity-not-found, public-form-disabled,
  honeypot triggers, time-check, X-Forwarded-For metadata + RFC1918
  rejection, browser/OS/device parsing, save_suspicious + save_log
  flag handling, redirect-back fallback).
- `components/entity_form_test.exs` (7 tests) — every cond branch in
  render/1 (missing slug, unknown entity, form disabled, fields empty,
  honeypot on, full happy-path).

### Existing LV smoke tests extended (handle_event coverage)

- `data_form_live_test`: validate / save / reset / generate_slug,
  new-form mount.
- `entity_form_live_test`: icon picker, field management (add / edit /
  cancel / delete / reorder), select-type options, public form
  settings, security toggles, backup toggles + export, save / reset.
- `entities_settings_live_test`: validate / save / reset_to_defaults,
  mirror toggles, export flows, import-modal flow.
- `data_navigator_live_test`: toggle_status (status cycle),
  restore_data, selection events, bulk_action (change_status /
  delete / empty-selection error path).

### Test infra additions

- `test/support/postgres/migrations/20260428000000_add_role_tables.exs`
  — new migration with `phoenix_kit_user_roles` +
  `phoenix_kit_user_role_assignments`. Required because
  `Mirror.Importer.create_entity_from_import/1` calls
  `Auth.get_first_admin/0` / `get_first_user/0`, both of which query
  the role-assignments table. Created as a new migration (rather than
  editing the original) so existing test DBs pick up the schema change
  without a `dropdb`.
- `test_helper.exs`: starts `PhoenixKit.TaskSupervisor` so async paths
  in `Mirror.Exporter` / context-fn `notify_*_event` don't crash with
  `:noproc` (publishing-Batch-5 test-helper precedent).

### Per-module coverage uplifts

| Module | Before | After |
|--------|--------|-------|
| Mirror.Exporter | 0% | 90.74% |
| Mirror.Importer | 0% | 79.30% |
| Mirror.Storage | 16.47% | 76.47% |
| SitemapSource | 0% | 76.79% |
| Components.EntityForm | 0% | 100% |
| Controllers.EntityFormController | 0% | 75.96% |
| ActivityLog | 23% | 53.85% |
| Web.EntitiesSettings | 25.43% | 81.17% |
| Web.EntityForm | 27.08% | 72.31% |
| Web.DataForm | 28.46% | 54.39% |
| UrlResolver | 33.61% | 64.71% |
| FormBuilder | 35.34% | 80.75% |
| EntityData | 50.15% | 79.30% |
| top-level PhoenixKitEntities | 53.55% | 86.17% |
| **Total** | **31.39%** | **67.33%** |

### What's still uncovered (deliberate residual)

- **Mix.Tasks.PhoenixKitEntities.Export / Import** —
  `Mix.Task.run("app.start")` requires a full app boot, not viable in
  the test sandbox.
- **PhoenixKitEntities.Migrations.V1** — runs at test_helper boot
  before `:cover` starts (canonical residual per workspace AGENTS.md).
- **PhoenixKitEntities.Web.DataView** — unrouted dead code (no callers
  anywhere; surfaced for boss decision above).
- **DataForm / DataNavigator handlers that push_patch to URLs outside
  the test router scope** (`/phoenix_kit/...` prefix) — would need an
  extended test router or parent-app integration tests.
- **ActivityLog `Logger.warning` + `:exit` rescue branches** — only
  reachable from sandbox-shutdown / non-Postgrex exception paths that
  aren't deterministically triggerable.
- **UrlResolver branches that depend on Languages being enabled
  (multilang mode)** — single-language mode is what tests run under.

## Open

None.
