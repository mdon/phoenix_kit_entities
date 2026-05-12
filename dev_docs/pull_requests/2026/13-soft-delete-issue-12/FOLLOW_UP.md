---
name: PR #13 follow-up — soft-delete review actions
description: Resolution of every CLAUDE_REVIEW.md finding for PR #13.
type: project
---

# PR #13 Follow-up — Soft-delete for EntityData

**Review:** [`CLAUDE_REVIEW.md`](./CLAUDE_REVIEW.md) (Claude Opus 4.7, 2026-05-04)
**Triage:** 2026-05-12

The post-merge review surfaced 9 non-blocking findings (1 MEDIUM, 4 LOW,
3 TRIVIAL/NIT). All 9 were verified live against `main` and fixed in
this batch.

## Fixed (Batch 1 — 2026-05-12)

- ~~**F1 (MEDIUM)** — `trash/2` and `restore_from_trash/2` ran the full
  per-field validation against the entity blueprint, blocking trash on
  records whose stored `:data` no longer satisfied the current
  `fields_definition` (e.g. the entity gained a required field after
  the row was created). Replaced both call sites with a focused
  `status_only_changeset/3` that only casts `:status`, `:metadata`,
  `:date_updated` and `validate_inclusion(:status, @valid_statuses)`.
  Mirrors the bulk variants' bypass-validation semantics so single +
  bulk paths agree.~~ — `entity_data.ex:1379-1413`
- ~~**F2 (LOW)** — `restore_from_trash/2` always returned to
  `"published"`, silently re-publishing a record that was `"draft"` or
  `"archived"` before being trashed. `trash/2` now stashes the row's
  prior `status` into `metadata["trashed_from_status"]`;
  `restore_from_trash/2` reads it back and restores to that value,
  defaulting to `"draft"` when absent. The stash key is dropped on
  restore so the metadata stays clean for any future re-trash. Bulk
  paths are unchanged (atomic `update_all`, no per-row metadata); a
  bulk-trashed-then-restored row picks the `"draft"` default — matches
  the review's safer-by-default recommendation.~~ — `entity_data.ex:1379-1413`
- ~~**F3 (LOW)** — `do_count_external_references/2` had a blanket
  `rescue _ -> acc` that swallowed every callback exception, including
  bugs in the parent-app callback itself. A broken callback silently
  reported "Used by 0 rows" with no log signal. Narrowed to
  `rescue e in [DBConnection.ConnectionError, Postgrex.Error]` with a
  `Logger.warning` on the caught shape; any other raise now propagates
  (consistent with `99ed89c`'s narrowing of the other broad rescues in
  this PR). Test updated: replaced the "ignores callbacks that raise"
  test (which pinned the old buggy contract) with two pinning tests —
  one asserts DB-availability raises are swallowed + logged, the
  other asserts non-DB raises propagate.~~ —
  `entity_data.ex:1882-1898`, `entity_data_trash_test.exs:568-602`
- ~~**F4 (TRIVIAL)** — `toggle_status` had a dead
  `"trashed" -> "trashed"` clause; the UI hides the toggle button for
  trashed rows so it was unreachable in practice but, if hit (stale
  tab / custom client), `update_data` would no-op and the cycle would
  silently swallow the click. Swapped to a catch-all `_ ->
  data_record.status` with a code comment naming the unreachability +
  the intentional no-op semantic.~~ — `data_navigator.ex:384-396`
- ~~**F5 (LOW)** — Docstring on `count_external_references/2`
  advertised an "admin trash bin" use case, but no LV call site in
  `lib/phoenix_kit_entities/web/` actually renders the count. Rewrote
  the example to frame it as the parent-app-consumption API that it
  is. The 2-arity form's N+1 fix stays in place as future-proofing.~~
  — `entity_data.ex:1790-1794`
- ~~**F6 (TRIVIAL)** — `permanent_delete` (single) and
  `do_bulk_permanent_delete/1` both leave their respective selections
  populated on the `:referenced_by_external` branch — intentional, so
  the user can fix references in the parent app and retry without
  re-checking each row. Added an inline comment on both call sites so
  the next contributor doesn't "fix" the missing reset.~~ —
  `data_navigator.ex:361-369`, `data_navigator.ex:608-614`
- ~~**F7 (LOW)** — Trash flash said "Restore it before 90 days to
  keep it" but no Oban purge worker enforces a 90-day retention. The
  copy was promising a deletion that doesn't happen. Replaced with
  "Record moved to trash. Restore from the trash view." — accurate
  and the test that asserts the flash via partial match
  (`render(view) =~ "moved to trash"`) still passes.~~ —
  `data_navigator.ex:313-318`
- ~~**F8 (LOW)** — `:reverse_references` reads from
  `Application.get_env(:phoenix_kit_entities, ...)` — a global OTP
  app env that cross-pollinates in a multi-tenant umbrella where two
  parent apps both register a callback for the same entity name. The
  "multiple callbacks per entity name" semantic was already
  documented, but the multi-tenant trap wasn't. Added an explicit
  paragraph to `AGENTS.md` under the Reverse-reference hook section.~~
  — `AGENTS.md:266-283`
- ~~**F9 (NIT)** — `bulk_delete/2`'s `rescue Postgrex.Error` scope
  spanned the entire function body, including the
  `PhoenixKitEntities.ActivityLog.log/1` call. If the activity-log
  write itself raised a `Postgrex.Error` (different table, different
  transaction — theoretical), it would be misclassified as
  `:referenced_by_external`. Extracted `run_bulk_delete_txn/1` and
  scoped the rescue to it; the activity-log call stays outside the
  rescue. Same fix on the single-record `delete/2`? — `do_delete/2`
  already passes the failing `repo().delete/1` result through
  `notify_data_event/3`, so a Postgrex error from notify-side code
  would not slip through the rescue anyway. Left as-is.~~ —
  `entity_data.ex:1949-1988`

## Skipped (with rationale)

None. All 9 findings addressed.

## Files touched

| File | Change |
|---|---|
| `lib/phoenix_kit_entities/entity_data.ex` | F1 focused changeset, F2 prior-status stash, F3 narrowed rescue + Logger import, F5 docstring, F9 rescue scope |
| `lib/phoenix_kit_entities/web/data_navigator.ex` | F4 catch-all + comment, F6 selection-preserved comment, F7 flash copy |
| `AGENTS.md` | F8 multi-tenant note |
| `test/phoenix_kit_entities/entity_data_trash_test.exs` | F3 contract update — replaced the broad-rescue test with two specific ones |

## Verification

- `mix compile` — clean (the unrelated `sortable_handle` Hex-pin
  warning is pre-existing — entities' Hex-pinned core doesn't yet have
  the new draggable_list attr from `phoenix_kit#516` companion work)
- `mix test` — **791 / 791 pass** (was 790 before; +1 from splitting
  F3's "ignores callbacks that raise" into "swallows DB raises" plus
  "propagates non-DB raises"). Pre-existing intermittent
  `DBConnection.ConnectionError` log lines from sandbox shutdown
  remain — same noise as in `main`.
- No behaviour regression on existing trash / restore tests: all
  setup-fixtures start from `status: "published"`, so F2's prior-
  status stash round-trips correctly back to `"published"` on
  restore. The bulk-restore tests (which bypass the stash because
  `update_all` doesn't run per-row logic) still land on `"published"`
  by default — unchanged.

## Open

None.
