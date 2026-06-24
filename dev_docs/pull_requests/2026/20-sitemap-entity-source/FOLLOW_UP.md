# Follow-up Items for PR #20

Triaged against `main` on 2026-06-24 (post-merge, commit `aba8508`).

## Resolved

### 1. `record_has_translation?/2` locale/field-key collision — FIXED

`BUG - MEDIUM`. The function treated every top-level `record.data` key as a
locale code, but only multilang records are locale-keyed; flat records are
field-keyed. A field named like a base locale (`"id"` → Indonesian, `"no"` →
Norwegian, `"it"` → Italian) made a flat record falsely "have a translation,"
emitting a localized URL that 404s — defeating the guard's own purpose.

**Resolution:** `lib/phoenix_kit_entities/sitemap_source.ex` —
`record_has_translation?/2` now gates on `PhoenixKit.Utils.Multilang.multilang_data?/1`
before reading top-level keys as locales. Flat records return `false` on the
non-default path (still emitted on the default path). Added
`alias PhoenixKit.Utils.Multilang`; corrected the misleading "`record.data` is
keyed by locale" comment.

### 2. Missing tests for the new per-language behavior — FIXED

`IMPROVEMENT - MEDIUM`. The PR added only negative non-default tests
(field-keyed records → empty). The feature (translated record → localized URL)
and the collision were untested.

**Resolution:** `test/phoenix_kit_entities/sitemap_source_test.exs` — added two
tests to the `collect/1` describe:

- *"non-default language emits a record that has a real per-locale translation"* —
  multilang record with `fr-FR` translation is emitted under `language: "fr"`;
  flat seed records are not. Locks the feature and proves the fix does not
  over-correct.
- *"flat record with a locale-colliding field key is not emitted for that language"* —
  entity with field key `"id"`, flat record, `language: "id"` → not emitted.
  Reproduces finding #1 and locks the fix.

### 3. `include_entities?/0` nested-module call flagged by `credo --strict` — FIXED

`NITPICK` (in PR code). The PR's `include_entities?/0` called
`PhoenixKit.Modules.Sitemap.include_entities?()` fully-qualified; `credo --strict`
wants nested modules aliased.

**Resolution:** `lib/phoenix_kit_entities/sitemap_source.ex` — added
`alias PhoenixKit.Modules.Sitemap` and call `Sitemap.include_entities?()`.

### 4. Pre-existing orphaned `:earmark` in `mix.lock` — FIXED (out of PR scope)

`NITPICK`. `mix precommit` was already red on `main`: `deps.unlock
--check-unused` flagged `:earmark` as locked-but-unused (leftover from the
`af082ef "lib upgrades"` commit; `mix.exs` does not declare it). Not introduced by
PR #20 but it aborts the gate before credo/dialyzer.

**Resolution:** `mix deps.unlock earmark` — removes the single orphaned line from
`mix.lock`. No code or `mix.exs` change.

### 5. Unreachable third clause of `record_has_translation?/2` flagged by dialyzer — FIXED

`NITPICK` (in PR code). `dialyzer` `pattern_match_cov`: the catch-all
`record_has_translation?(_record, _language) -> false` can never match — the
`nil` and `is_binary/1` clauses already cover the argument type `nil | binary()`.

**Resolution:** `lib/phoenix_kit_entities/sitemap_source.ex` — removed the dead
clause; nil `data` stays handled via `Multilang.multilang_data?/1`.

## Open

None.

## Validation note

This module is a library with no standalone DB in CI; integration tests
auto-exclude when Postgres is absent (`test/test_helper.exs`). In **this review
environment** no Postgres server was reachable (`localhost:5432` refused) and the
`psql` client is not installed, so the two added integration tests could not be
executed here — they are tagged `:integration` (via `DataCase`) and run wherever
`phoenix_kit_entities_test` exists. The authoritative gate, `mix precommit`
(compile `--warnings-as-errors` + `deps.unlock --check-unused` + `hex.audit` +
format-check + `credo --strict` + dialyzer), was run against the code change; see
`CLAUDE_REVIEW.md` and the chat summary for the result.

## Not changed (deliberate)

- The auto-registration callback, `include_entities?/0` fall-open rescue, and the
  `prepend_index_entry` localized-index logic are correct as written — see
  "Non-issues considered" in `CLAUDE_REVIEW.md`.
