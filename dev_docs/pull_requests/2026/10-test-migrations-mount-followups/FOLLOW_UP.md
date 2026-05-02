# Follow-up Items for PR #10 (Drop hand-rolled test migrations + close mount/3 review follow-ups)

PR #10 was a follow-up to PR #9 — Batch 6 (test migration cleanup,
−521 lines DDL, +5 lines fixture corrections) and Batch 7 (mount/3 →
handle_params/3 in `data_form.ex` / `entity_form.ex` /
`entities_settings.ex`). Merged 2026-04-29.

The reviewer's six findings + four "Suggested follow-ups" are
triaged below against current code (HEAD = `2fbeaa2`).

## Fixed (pre-existing)

- ~~**§1 `{:ok, socket}` wrapper on hydrate helpers**~~ —
  `lib/phoenix_kit_entities/web/data_form.ex:85` (`hydrate_data_form/6`)
  and `web/entity_form.ex:55` (`hydrate_entity_form/4`) now return
  socket directly; callers in `handle_params/3` wrap with
  `{:noreply, hydrate_*(...)}`. The vestigial `{:ok, _}` shape the
  reviewer flagged is gone.
- ~~**§3 "load admin dashboard" comment**~~ —
  `lib/phoenix_kit_entities/web/entities_settings.ex:47-49` already
  carries the warning the reviewer suggested verbatim:
  > Canonical "load admin dashboard" path. Runs once on initial
  > connected mount; would also re-run on any future `push_patch/2`
  > to this LV. Keep cheap-looking work out of here — every read
  > below multiplies on patch.
- ~~**Suggested follow-up #3 — "no module-owned DDL" rule in
  AGENTS.md**~~ — `AGENTS.md:429` documents the rule
  ("`test_helper.exs` runs `Ecto.Migrator.run/4` against
  `PhoenixKit.Migration` — no module-owned test DDL"); `AGENTS.md:169`
  cross-references core's V17/V40/V58/V67/V74/V81 as the owners of
  the entities tables.

## Fixed (Batch 1 — 2026-05-02) (commit `2fbeaa2`)

- ~~**§5 placeholder bcrypt hash in user-seed fixtures**~~ —
  Added `PhoenixKitEntities.DataCase.valid_test_password_hash/0`
  computed once at compile time via
  `@valid_test_password_hash Bcrypt.hash_pwd_salt("test")`. Returns a
  real bcrypt hash whose plaintext is `"test"`, suitable for
  `phoenix_kit_users.hashed_password` seeds. Both call sites updated:
  - `test/phoenix_kit_entities/mirror/importer_test.exs:35`
  - `test/phoenix_kit_entities/mix_tasks/import_test.exs:37`

  The previous `"$2b$12$placeholder"` literal was a syntactically
  valid bcrypt prefix but a malformed payload —
  `Bcrypt.verify_pass/2` against it would crash rather than return
  `false`. Today's tests don't authenticate, but the foot-gun is
  removed for any future caller.

## Skipped (with rationale)

- **§2 hydrate re-runs on every patch** — Reviewer marked this
  "Latent / not currently triggering" and explicitly bounded scope
  with "**No change requested in this PR** — flagging for the next
  person who touches the LV." Verified neither LV patches itself
  (`grep -rn "live_patch\|push_patch" lib/phoenix_kit_entities/web/`
  returns only `entities.ex:54` and `data_navigator.ex`, both
  cross-LV navigations). `Phoenix.PubSub.subscribe/2` is idempotent
  per-process, so even if patching is added later the duplicate
  subscribe is a no-op rather than a duplicate-message bug. A
  defensive "have we hydrated for this URI?" guard would be
  speculative — adding code we can't currently exercise.
- **§4 / Suggested follow-up #1 — CHANGELOG + version bump for
  `PhoenixKitEntities.Migrations.V1` removal** — Releases (version
  bumps, CHANGELOG entries) are owned by the project maintainer per
  the workspace memory rule, not auto-applied by the sweep
  pipeline. Current version is `0.1.6`; a `0.2.0` bump for the
  breaking public-module deletion is appropriate at the next
  release cut. Surfaced for Max.
- **Suggested follow-up #2 — Drop `{:ok, socket}` wrapper** —
  superseded by "Fixed (pre-existing)" above.
- **Suggested follow-up #4 — `valid_test_password_hash/0`
  helper** — superseded by "Fixed (Batch 1)" above.

## Note

- **§6 `account_type = 'person'`** — confirmation-only finding; the
  fixture migration from `'personal'` (hand-rolled test schema) to
  `'person'` (production CHECK constraint) is the textbook example of
  the drift bug the test-migration cleanup was designed to surface.
  Already captured in PR #10's body and the workspace
  `migration_cleanup.md` doc.

## Files touched

| File | Change |
|---|---|
| `test/support/data_case.ex` | Added `valid_test_password_hash/0` helper backed by a compile-time `Bcrypt.hash_pwd_salt/1` module attribute |
| `test/phoenix_kit_entities/mirror/importer_test.exs` | Replaced `"$2b$12$placeholder"` literal with `valid_test_password_hash()` call |
| `test/phoenix_kit_entities/mix_tasks/import_test.exs` | Same replacement as above |

## Verification

- `mix compile` passes for the test-support compilation; the only
  warnings are the documented standalone-vs-parent gap (the local
  module schema references `:position` on `phoenix_kit_entities`,
  added by a not-yet-published V108 in core; canonical channel is
  via `phoenix_kit_parent` per `feedback_run_tests_via_parent.md`).
- `valid_test_password_hash/0` is reachable from both fixtures via
  `use PhoenixKitEntities.DataCase` (the `using` block already
  imports the case module).
- The fixture inserts that previously stored `"$2b$12$placeholder"`
  now persist a verifiable bcrypt hash — a future test can call
  `Bcrypt.verify_pass("test", row.hashed_password)` and get `true`
  back.

## Open

None.
