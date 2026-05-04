---
name: PR #13 review — soft-delete for EntityData
description: Post-merge code review of PR #13 (issue #12) against ecto-thinking and phoenix-thinking checklists.
type: project
---

# PR #13 Review — Soft-delete for EntityData (trash / restore + friendly FK error)

**Reviewer:** Claude (Opus 4.7, 1M context)
**Date:** 2026-05-04
**PR:** https://github.com/BeamLabEU/phoenix_kit_entities/pull/13
**Issue:** https://github.com/BeamLabEU/phoenix_kit_entities/issues/12
**Author:** @mdon (Max Don)
**Branch:** `fix/issue-12-soft-delete` → `main` · merged 2026-05-04
**Net diff:** +1943 / −123 across 10 files
**Skills consulted:** `elixir:using-elixir-skills`, `elixir:ecto-thinking`, `elixir:phoenix-thinking`
**Verdict:** Approve with non-blocking follow-ups *(post-merge review — PR already merged)*

---

## Summary

Issue #12 was a real bug: parent apps (e.g. an orders app) carry FK
references like `orders.status_uuid → phoenix_kit_entity_data.uuid`,
so an admin clicking Delete on a referenced controlled-vocabulary row
hit Postgres `23503` and a 500. Two options were on the table — a new
`deleted_at` column, or reusing the existing `status` string with a
`"trashed"` sentinel. Max went with the second (correctly — every other
PhoenixKit table uses a status-string convention; a column would have
fragmented the workspace), and built out the full UX: trash filter view,
restore, permanent-delete with friendly flash, bulk variants, plus a
hook for parent apps to surface "used by N rows" counts.

Verification was done locally and on the `phoenix_kit_parent` workspace.
The companion C12/C12.5 quality sweep (`574a809`, `99ed89c`, `2233ab3`)
adds @specs, `phx-disable-with` on bulk buttons, narrows three pre-existing
broad rescues, and adds a 2-arity form of `count_external_references`
to skip per-call preloads.

I read the merged diff against `main` (`e0ed29a..e63d1ce`) and audited the
new code against the **ecto-thinking** soft-delete patterns, **phoenix-thinking**
Iron Law (no DB in mount) and form-handling rules, and the standard
authorization / audit-coverage / FK-error-handling rubric.

---

## What's right

A short, non-exhaustive list — these are the parts I checked and confirmed
hold up. Skipping the obvious "feature works" stuff.

- **Status-string sentinel was the right choice.** Aligns with
  `phoenix_kit_publishing.posts.status` and `phoenix_kit_catalogue.items.status`,
  no migration, no schema bifurcation, slug uniqueness preserved (a
  `deleted_at` approach would have needed a partial unique index to
  preserve slug-uniqueness across trash). The 4-state set
  `{draft, published, archived, trashed}` reads cleanly.
- **Default-list filtering is comprehensive and consistent.** Every
  public read path (`list_all/1`, `list_by_entity/2`, `list_by_entity_and_status/3`,
  `search_by_title/3`, `search_by_title/2` in alias form, `count_by_entity/2`)
  threads through the same `exclude_trashed/2` helper with `include_trashed: true`
  as the opt-in escape hatch. Mirror exporter inherits this naturally.
  The implicit-scoping case where `status` already names a non-trashed
  status (e.g. `list_data_by_status("draft")`) skips the redundant
  `where status != 'trashed'` — neat, and the docstring calls it out.
- **`get_by_slug/2` deliberately surfaces trashed rows.** Documented and
  pinned by a test (`get_by_slug still finds trashed records`). This is
  the right semantics — slug uniqueness is a DB constraint, and
  resolving "/posts/foo-bar" to a 404 instead of a hidden trashed row
  would let admins create a clashing slug from a fresh row.
- **FK-violation handling on `delete/2` is properly belt-and-braces.**
  Catches both `Ecto.ConstraintError` (the wrapper raised when the
  schema lacks a declared `foreign_key_constraint` for the inbound
  reference — which it does, because the FK lives in the parent app)
  *and* raw `Postgrex.Error`. The dispatch through `foreign_key_or_not_null_violation?/1`
  matches both atom-form (`:foreign_key_violation`) and string SQLSTATE
  (`"23503"`) so it survives Postgrex internals shifts. Real bugs still
  surface — the `else` branch reraises with the original stacktrace.
- **Audit log threads through every branch.** `entity_data.trashed`,
  `entity_data.restored`, `entity_data.bulk_trashed`, `entity_data.bulk_restored`
  all land via `notify_data_event` / explicit `ActivityLog.log` in the
  bulk paths. The `:referenced_by_external` rejection logs an
  `entity_data.deleted` error row via `log_data_error_activity` so
  audit coverage is complete on both happy and unhappy paths. PII-safe
  metadata (`{"count" => n}` only).
- **Authorization gate on every event.** All three new per-record
  events (`trash_data`, `restore_from_trash`, `permanent_delete`) and
  both new bulk variants (`bulk_action: trash`, `bulk_action: restore_from_trash`,
  `bulk_action: permanent_delete`) check `Scope.admin?(...)` before any
  DB access. Consistent with the prior pattern.
- **Bulk paths use `update_all` for atomicity.** `bulk_trash/2` and
  `bulk_restore_from_trash/2` use a single `update_all` with a `where`
  clause that scopes by current status — `bulk_trash` skips already-trashed
  rows via `where: d.status != ^@soft_delete_status`, `bulk_restore_from_trash`
  only touches rows currently `"trashed"`. Race-free, no per-row N+1.
- **`broadcast_bulk_change/1` does the right thing.** Re-queries
  `(entity_uuid, uuid)` pairs after the bulk write so each affected
  entity LV gets a `data_updated` event. No relying on the assumption
  that all UUIDs share an entity.
- **Mirror exporter naturally excludes trashed.** `list_data_by_entity/2`
  uses the default `exclude_trashed`, so the exported JSON file drops
  trashed rows on the next re-export. Pinned by
  `mirror/exporter_test.exs:trashed records are excluded from the data array (issue #12)`.
  And `notify_data_event(:trashed, _)` triggers a re-export, so the
  file stays in sync without an admin re-export step.
- **Two-arity `count_external_references/2` is the right N+1 fix.** The
  1-arity fallback preloads `:entity` per call; the 2-arity form takes
  an already-loaded entity and skips the preload. Internal dispatch
  through `do_count_external_references/2` avoids the recursion trap
  the obvious "delegate to 1-arity" implementation would have hit on
  orphan records (entity preloaded as `nil`). Single-clause sentinel
  `{:error, _} -> 0` (`def count_external_references(%__MODULE__{}, _), do: 0`)
  catches malformed callers.
- **Phase 2 quality sweep is genuinely tightening, not cosmetic.**
  - `entity_form_controller.ex:495` — `String.to_integer + rescue _`
    swapped for `Integer.parse/1` with a `with`/`else` chain that
    pins `{int, ""}` (so `"123abc"` doesn't slip through as `123`).
    Drops the rescue clause entirely.
  - `sitemap_source.ex:140` — `rescue _ -> nil` now logs the error
    inspect, matching the canonical pattern at the other two rescues
    in the same file. Failures are no longer silent.
  - `sitemap_source.ex:148` — `enabled?/0` gained `catch :exit, _ -> false`
    matching the boot-resilience shape from `phoenix_kit_entities.ex`.
- **Test coverage is thorough.** +130 net tests, the new
  `entity_data_trash_test.exs` (49 tests, 699 lines) builds transient
  `_trash_test_parent` tables that mirror issue #12's exact
  `NOT NULL REFERENCES … ON DELETE RESTRICT` shape — so the FK-violation
  paths are exercised against a real parent FK, not a synthetic
  `Postgrex.Error{}`. The DataNavigator describe block (18 tests)
  pins authorization, empty-selection guards, and the bulk-bar
  branching by view.

---

## Findings

Numbered F-prefix, severity tagged. None are merge-blockers (PR is
already merged).

### F1 · `trash/2` runs the full record-validating changeset · MEDIUM

`trash/2` and `restore_from_trash/2` both go through `changeset/2`
(L1133-1140, L1160-1165), which runs `validate_data_against_entity/1`
— the full per-field validation against the entity blueprint.

```elixir
def trash(%__MODULE__{} = entity_data, opts) when is_list(opts) do
  entity_data
  |> changeset(%{status: @soft_delete_status})
  |> repo().update()
  |> notify_data_event(:trashed, opts)
end
```

If a record's stored `:data` no longer validates against its entity
definition (e.g. an admin added a new required field to the entity
after this record was created, or tightened a regex), trashing it
will return `{:error, %Ecto.Changeset{}}`. The LV catches this as
`{:error, _changeset}` and flashes the generic `"Failed to trash record"`
— with no path to actually get the row out of the way.

The bulk variants don't have this problem — they go through `update_all`
and bypass changesets entirely. So `bulk_trash([uuid])` will succeed
where `trash(record)` fails, which is a confusing inconsistency.

**Recommendation:** Build a focused changeset (cast `[:status, :date_updated]`,
validate inclusion only) for the trash/restore paths. The full record
validation is appropriate when editing data, not when changing only
the status field. A user wanting to throw away a now-invalid record
shouldn't be blocked by validation that no longer applies.

```elixir
defp trash_changeset(entity_data, status) do
  entity_data
  |> cast(%{status: status, date_updated: UtilsDate.utc_now()}, [:status, :date_updated])
  |> validate_inclusion(:status, @valid_statuses)
end
```

### F2 · `restore_from_trash/2` always restores to `"published"` · LOW

```elixir
def restore_from_trash(%__MODULE__{status: @soft_delete_status} = entity_data, opts) do
  entity_data
  |> changeset(%{status: "published"})
  |> ...
```

A record that was `"draft"` or `"archived"` before being trashed will
come back as `"published"` after restore. The previous status is
unrecoverable. For a controlled-vocabulary use case (the issue #12
motivation) this rarely matters — those rows are practically always
published. But a draft post that gets accidentally trashed and
restored will silently become live.

**Recommendation:** Either (a) document the "always publishes" semantic
in the docstring as deliberate (currently it's not called out), or
(b) stash the prior status in `metadata` on `trash/2` and read it back
on `restore_from_trash/2`, defaulting to `"draft"` when missing. (b)
is the safer default — a trashed record returning to `"draft"` rather
than `"published"` matches the "least-surprise" principle.

### F3 · Broad rescue in `do_count_external_references/2` · LOW

```elixir
|> Enum.reduce(0, fn {_name, fun}, acc ->
  try do
    count = fun.(entity_data.uuid)
    if is_integer(count) and count >= 0, do: acc + count, else: acc
  rescue
    _ -> acc
  end
end)
```

The blanket `rescue _ -> acc` swallows everything from the
parent-app callback — including bugs in the callback itself, not just
DB-availability hiccups. Sits awkwardly next to `99ed89c`'s narrowing
of the other broad rescues in this PR.

**Recommendation:** Narrow to `rescue e in [DBConnection.ConnectionError,
Postgrex.Error] -> Logger.warning("reverse_references callback ... failed: #{inspect(e)}"); acc`,
matching the canonical shape from the sitemap fix. Bugs in the callback
will now surface in logs instead of silently zeroing the count, which
is the surprising current behavior — a broken callback shows
"Used by 0 rows" with no indication anything went wrong.

### F4 · `toggle_status` has dead "trashed" branch · TRIVIAL

```elixir
new_status =
  case data_record.status do
    "draft" -> "published"
    "published" -> "archived"
    "archived" -> "draft"
    "trashed" -> "trashed"
  end
```

The trashed→trashed clause is unreachable: the per-row UI branch
shows Restore-from-trash + Delete-forever for trashed records and
hides the cycle button entirely (DataNavigator.ex L1521-1539). The
clause exists to keep the `case` total against the type, but `update_data`
will then no-op the status update and the cycle silently does nothing.

**Recommendation:** Either remove the clause and let it raise
`CaseClauseError` (defensive — it'd surface a UI mistake immediately),
or keep but add a comment that this is unreachable safety. Currently
neither — silent acceptance is the worst of both.

### F5 · `count_external_references` advertised but unused · LOW

The N+1 fix in `2233ab3` added a 2-arity form so admin views rendering
many records can pass the entity once. But grepping the LV side of
this PR — DataNavigator doesn't actually call `count_external_references`
anywhere yet. The "Used by N rows" hint is a hook for parent apps,
not yet a feature in the admin UI.

This isn't wrong (the API is intentionally for parent-app consumption),
but the PR description and the docstring's "rendering many records
(e.g. the admin trash bin)" phrasing imply the trash view does
something with this — it doesn't. A future PR could surface the count
on the trash filter view as a delete-blocker hint.

**Recommendation:** Tighten the docstring example to remove the
"admin trash bin" reference (or follow up with a PR that actually
renders the count on the trash list). The 2-arity form is still
correct future-proofing.

### F6 · `permanent_delete` per-record path doesn't refresh on FK error · TRIVIAL

```elixir
def handle_event("permanent_delete", %{"uuid" => uuid}, socket) do
  ...
  case EntityData.delete(data_record, actor_opts(socket)) do
    {:ok, _data} ->
      socket |> refresh_data_stats() |> apply_filters() |> put_flash(:info, ...)

    {:error, :referenced_by_external} ->
      put_flash(socket, :error, ...)   # no refresh
```

The FK-error branch flashes but skips `refresh_data_stats`/`apply_filters`,
which is fine — nothing changed in the DB. But the bulk-variant
`do_bulk_permanent_delete/1` also skips on the FK-error branch (and
also leaves `selected_uuids` populated). Consistent, but it does mean
a user clicking Permanent-delete on a multi-select that hits the FK
error keeps their selection — which is probably intentional (let them
adjust and retry) but could be called out in code or doc.

**Recommendation:** Comment the `selected_uuids` non-clear on the
FK-error path so a future contributor doesn't "fix" it.

### F7 · Trash retention policy mentioned in flash but not enforced · LOW

```elixir
gettext("Record moved to trash. Restore it before %{days} days to keep it.", days: 90)
```

The flash says 90 days. There is no scheduled job purging trashed
records older than 90 days — `bulk_delete` on aged trashed rows is
manual-only. Either the flash should drop the days reference, or a
follow-up PR should add an Oban purge worker (the `oban-thinking`
skill applies — unique-by-day, low priority, dry-run-toggle).

**Recommendation:** Drop the days copy unless the purge job is
imminent. Promising a deletion that doesn't happen is worse than
just calling it the trash bin.

### F8 · `:reverse_references` config is application-global · LOW

```elixir
:phoenix_kit_entities
|> Application.get_env(:reverse_references, [])
```

Reads from the OTP app config — fine for a single-tenant deploy. But
PhoenixKit ships into multi-tenant hosts (e.g. an umbrella with
multiple parent apps each holding their own FKs). All parent apps
share one global list of `{entity_name, count_fn}` tuples. If two
apps both define `"order_status"`, both callbacks fire for every
record. Not a bug — that's documented as the "multiple callbacks per
entity name" feature — but worth being aware of as a coupling risk.

**Recommendation:** Document the global-list semantic explicitly so
host apps don't accidentally cross-pollinate. Long-term, a per-entity
configuration on the entity blueprint itself would scale better.

### F9 · `bulk_delete` rescue scope · NIT

```elixir
def bulk_delete(uuids, opts \\ []) when is_list(uuids) do
  {count, _} =
    result =
    from(...)
    |> repo().delete_all(...)

  PhoenixKitEntities.ActivityLog.log(%{
    action: "entity_data.bulk_deleted",
    ...
    metadata: %{"count" => count, ...}
  })

  result
rescue
  e in Postgrex.Error -> ...
```

The rescue covers the whole function body, including the
`ActivityLog.log` call. If the audit log write itself raises a
`Postgrex.Error` for some reason (extremely unlikely — different table,
different transaction), it'd be misclassified as `:referenced_by_external`.
The risk is theoretical, but the cleaner shape is to wrap only the
`delete_all` call.

**Recommendation:** Move the `try/rescue` to scope just the
`from(...) |> repo().delete_all(...)` expression. Same fix on the
single-record `delete/2`.

---

## Skill audit

- **`elixir:ecto-thinking`** — Soft-delete via status-string sentinel
  fits the "schemas are not just tables" principle (`status` is the
  effective state column). No N+1 in default queries. The 2-arity
  `count_external_references` is a textbook fix for the cross-context
  preload N+1 the skill warns about.
- **`elixir:phoenix-thinking`** — Iron Law respected: no DB queries
  in `mount/3`. New `handle_event` clauses gate on auth before any DB
  access. `phx-disable-with` on every bulk button is a phoenix-thinking
  best-practice. Per-row `data-confirm` for permanent-delete is a
  reasonable browser-side guard (server still re-validates auth +
  state).
- **`elixir:otp-thinking`** — N/A; this is a context-layer change with
  no new processes.
- **`elixir:oban-thinking`** — Relevant for the F7 follow-up (90-day
  trash purge worker). Not in this PR.

---

## Stale-state / regression checklist

- `mix format --check-formatted` — PR description says clean, not
  re-verified locally.
- `mix credo --strict` — PR description says clean.
- `mix compile --warnings-as-errors` — PR description says clean.
- `mix test` — 775/775 per PR description, 5/5 stability.
- Browser smoke: trash → restore → permanent-delete loop, bulk
  variants, `phx-disable-with` rendering — all per PR description.

I did not re-run the test suite from this review. The PR description
verification claims are detailed and consistent with the diff.

---

## Verdict

Approve. The soft-delete reframe was the right architectural call,
the FK-violation handling is properly defensive on both single-record
and bulk paths, audit coverage is complete, and the Phase 2 quality
sweep tightens three pre-existing rough edges that were unrelated to
the feature itself. Tests pin the meaningful invariants (slug
uniqueness across trash, mirror exclusion, parent-FK violation
behavior, bulk-bar branching).

The follow-ups above are non-blocking — F1 (full-record changeset on
trash) is the most impactful and worth addressing in a follow-up PR
since it can surface as a confusing user-facing failure on records
with stale data. F7 (the 90-day flash without an enforcing job) is
the most user-visible inconsistency.

---

## Suggested follow-up tickets

1. **F1** — Switch `trash/2` and `restore_from_trash/2` to a focused
   `trash_changeset` that only casts/validates `:status` and
   `:date_updated`. Mirror the bulk variants' bypass-validation
   semantics.
2. **F2** — Stash prior status in `metadata` on trash, restore to it
   (default `"draft"`) on restore.
3. **F3** — Narrow the rescue in `do_count_external_references/2` to
   the DB-availability shape and log on failure.
4. **F7** — Either drop the "90 days" copy from the trash flash, or
   add an Oban worker that enforces it.
5. **F8** — Document the global-list semantic of `:reverse_references`
   in `AGENTS.md` explicitly.
