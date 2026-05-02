# Follow-up Items for PR #11 (Drag-and-drop reorder + quality sweep)

PR #11 merged to `main` at `f051f36` on 2026-05-02. Post-merge review
(`CLAUDE_REVIEW.md`) surfaced six findings (F1–F7; F6 deferred as info).
This follow-up batch closes F1–F5 and F7. Bumps version to `0.1.7`.

Triage against current code (HEAD after this commit):

## Fixed in this batch

- **F1 — `Scope.admin?` gate on `Web.Entities` mutating handlers** —
  `reorder_entities`, `archive_entity`, `restore_entity` in
  `lib/phoenix_kit_entities/web/entities.ex` now gate on
  `Scope.admin?(socket.assigns.phoenix_kit_current_scope)` before
  proceeding, matching the existing defense-in-depth pattern in
  `Web.DataNavigator`. Non-admin pinning test added to
  `entities_live_test.exs`.

- **F2 — Duplicated card-view markup in `data_navigator.ex`** —
  Collapsed the `if @selected_entity do ... else ... end` card-view
  branch (~80 duplicated lines) into a single `<.draggable_list>` call
  with `draggable={not is_nil(@selected_entity) and length(...) > 1}`.
  Uses the `:draggable` boolean attr shipped in the updated
  `phoenix_kit` dep. Net: −80 lines, zero behavioral change.

- **F3 — Race-tolerant comment on `maybe_add_entity_position/1`** —
  Added documentation to `lib/phoenix_kit_entities.ex` acknowledging
  the MAX+1 read-then-write race and the `date_created` tiebreaker.

- **F4 — `ArgumentError` fallthrough on `position_update_query/2`** —
  Third function head in `lib/phoenix_kit_entities/entity_data.ex`
  raises `ArgumentError` with a clear message for non-binary scope
  values, replacing the opaque `FunctionClauseError`. Pinning test
  added to `entity_data_extras_test.exs`.

- **F5 — Log + flash on `ensure_manual_sort/1` failure** —
  `lib/phoenix_kit_entities/web/data_navigator.ex`: error branch now
  `Logger.error`s with entity uuid + changeset errors (grep-able),
  and the caller `apply_record_reorder/2` emits a warning flash
  ("order may not survive a refresh") so the user isn't left guessing.

- **F7 — Audit row shape documented in `AGENTS.md`** —
  Added a table under "Drag-and-drop reorder API" covering
  success/error/rejected branches for the `entity.reordered` and
  `entity_data.reordered` audit rows.

## Deferred

- **F6 — N+1 `update_all` in transaction (1000 round trips)** —
  Flagged as info-only. Bounded by the 1000-uuid cap. Acceptable for a
  per-page admin action. Revisit if reorder performance becomes a
  complaint.
