---
name: PR #15 review — Phase 2 re-validation + parent_uuid + Create-and-Return + dropdowns + DnD handle
description: Post-merge code review of PR #15 against ecto-thinking, phoenix-thinking, and the security rubric.
type: project
---

# PR #15 Review — Phase 2 re-validation + parent_uuid + Create-and-Return + dropdowns + DnD handle

**Reviewer:** Claude (Opus 4.7, 1M context)
**Date:** 2026-05-12
**PR:** https://github.com/BeamLabEU/phoenix_kit_entities/pull/15
**Author:** @mdon (Max Don)
**Branch:** `mdon/main` → `main` · **MERGED**
**Net diff:** +1756 / −329 across 18 files
**Skills consulted:** `elixir:using-elixir-skills`, `elixir:ecto-thinking`, `elixir:phoenix-thinking`
**Verdict:** Approve with non-blocking follow-ups *(post-merge — PR already merged at 14d1ff9)*

---

## Summary

Six commits bundled on top of post-PR-#14 `main`. Three feature
batches + two PR follow-up docs + one re-validation sweep:

1. **`parent_uuid` self-FK on `EntityData`** — adds a
   `belongs_to(:parent)` / `has_many(:children)` pair, three changeset
   validations (self-parent, same-entity, no-cycle), a depth-ordered
   tree helper (`list_tree/2`), a descendant collector
   (`descendant_uuids/3`), and a hard-delete child-block (`:has_children`).
   Trashed children are nullified inside the delete transaction so the
   self-FK doesn't bounce the parent's deletion. Parent picker rendered
   on both branches of the DataForm.
2. **"Create/Update and Return" buttons** — second submit button per
   action row, captures `_live_referer` from `get_connect_params/1` at
   WS-connect, validates as an internal admin path, drops self-referrer
   on reload, falls back to `/admin/entities`.
3. **Tables overhaul** — switches action columns to `<.table_row_menu>`
   kebab dropdowns (canonical workspace pattern), WordPress-style depth
   indent in DataNavigator (`— ` × depth), handle-only DnD via
   `:sortable_handle`, reorder confirmation flash via `sortable:flash`
   push-event keyed on `moved_id`.
4. **PR #13 follow-up (F1–F9)** — focused `status_only_changeset/3`
   for trash/restore, prior-status stash in metadata, narrowed
   `do_count_external_references/2` rescue with `Logger.warning`,
   `bulk_delete` rescue scope tightened.
5. **PR #14 follow-up stub** — canonical record for the two nits
   already resolved in the review pass.
6. **Phase 2 re-validation** — closes H1 (open redirect), H2/H3
   (race on `delete` / `bulk_delete`), H4 (`:has_children` Errors test),
   M1–M3 (save-and-return LV test, permanent_delete `:has_children`
   LV test, parent picker LV tests), plus ~40 `@spec` backfill.

The PR self-reports **800 / 800 tests pass** with 3× consecutive
stable runs.

I read the merged diff (`gh pr diff 15`, 3 223 lines) and audited:
- the changeset validations against the **ecto-thinking** changeset
  composition + transaction-boundary checklist,
- `redirect_back/2` and `referer_to_return_path/1` against the
  open-redirect rubric,
- `mount/3` and `assign_parent_options/4` against the **phoenix-thinking**
  Iron Law (no DB in mount),
- the new tests for coverage of error branches and rejection paths.

---

## What's right

A non-exhaustive list — these are the parts I checked and confirmed
hold up.

- **The status-string + metadata stash for trash/restore is the right
  shape.** `status_only_changeset/3` bypasses per-field validation
  against the entity blueprint so a row whose `:data` no longer
  satisfies the current `fields_definition` can still be trashed.
  `trashed_from_status` in `metadata` round-trips the prior status
  through restore; `"draft"` default for bulk-trashed rows is the
  safer-by-default call. Both directions are pinned by tests.
- **Race-classification on `delete/2` and `bulk_delete/2`.** Folding
  `has_live_children?` / `has_external_live_children?` inside
  `Repo.transaction` doesn't *eliminate* the race (Postgres FK row
  locks already do that — see follow-up A1 below) but it makes the
  expected case return the more accurate `:has_children` instead of
  the misleading `:referenced_by_external`. The DB-level FK still
  catches the genuine race. Both error branches log a `db_pending`
  activity entry. Tests cover both single + bulk paths for the
  live-child block and the trashed-child pass-through.
- **`nullify_trashed_children/1` inside the txn** lets the parent
  delete go through without tripping the self-FK on trashed orphans
  — a clean alternative to `ON DELETE SET NULL` at the DB layer
  (which would also nullify on accidental deletes; the txn-scoped
  approach keeps the constraint strict). Soft-delete semantic
  ("trashed children don't count as live children") is consistent
  between the single and bulk paths.
- **Open-redirect fix on `redirect_back/2`.** Parsing the Referer,
  requiring `http`/`https` + same-host match against `conn.host`,
  and returning a path-only relative redirect is the textbook fix.
  Falling back to `/` for any failure is the correct default.
  Query string reattached so the user lands back on their filters.
  *(Caveat — see follow-up B1: the path itself could still be a
  protocol-relative URL that Phoenix's own `redirect(to:)` guard
  rejects with `ArgumentError`. Not exploitable, but rough.)*
- **`_live_referer` validation in `entity_form.ex`.** Captured
  inside `if connected?(socket)` so the HTTP mount doesn't depend
  on connect params, and the `drop_self_referer/2` pass handles
  the edit-page-reload case so "Update and Return" doesn't no-op.
  Storing the validated path rather than the raw referrer means
  there's nothing for an attacker to inject into a later redirect.
- **Tree helpers are pure data transforms.** `build_tree/3` /
  `walk_tree/3` / `group_by_parent/1` operate on the
  already-fetched list — no per-row DB queries. The `known_uuids`
  defensive root-promotion (rows whose `parent_uuid` points outside
  the input set surface as roots) means a misaligned parent
  reference can't *hide* a row from the admin view. Same defense
  on the DataNavigator's `tree_order/1`.
- **`maybe_tree_order/4` falls back cleanly.** Only depth-orders
  when the slice is coherent (`status="all"`, search=`""`); for
  filtered or searched views it returns flat sibling order with
  zero depths so the template renders without indentation. The
  trade-off is documented in a comment and matches WordPress's
  own behaviour.
- **`@max_ancestor_depth 64` cycle guard.** Bounded walk so a
  pre-existing cycle in the DB (shouldn't happen, but defensive)
  can't loop the validator forever. Reasonable depth — a tree
  this deep is a UX bug regardless of the validator.
- **Test coverage threads every meaningful branch:**
  - `entity_data_parent_test.exs` — 15 tests covering self-parent,
    cross-entity, cycle (3-deep), NULL parent, descendant collector
    (root + leaf + nil), single + bulk hard-delete with live and
    trashed children.
  - `data_form_live_test.exs` — happy path via `form/3`, plus three
    rejection paths via `render_hook` to bypass the form helper's
    option allowlist and exercise the changeset-layer validations.
  - `entity_form_live_test.exs` — Update-and-Return navigates,
    plain Update stays put.
  - `data_navigator_live_test.exs` — `:has_children` flash on
    permanent_delete with audit-log assertion.
  - `errors_test.exs` — exact-translated-string pin for
    `:has_children` (no `is_binary` smell).
- **`@spec` backfill on ~40 public functions** across
  `entity_data.ex` and `phoenix_kit_entities.ex` — including the
  multi-clause `search_by_title`, `search_data`, `entities_children`,
  `resolve_language`, `resolve_languages`. Dialyzer-clean from this
  side.
- **PR #13 follow-ups (F1–F9) are all genuine improvements** — the
  narrowed `do_count_external_references/2` rescue with
  `Logger.warning` is the right call (a buggy parent-app callback
  reporting "Used by 0 rows" silently was the surprising default
  this guard was supposed to prevent); the `bulk_delete` rescue
  scope tightening via `run_bulk_delete_txn/1` prevents an
  ActivityLog raise from being misclassified as
  `:referenced_by_external`.

---

## Findings

Sorted MEDIUM → LOW → NIT. All non-blocking; the PR is merged.

### A1 — MEDIUM — Race window on parent-cycle validation

`validate_parent_not_descendant/1` walks the ancestor chain at
*changeset validation* time (`entity_data.ex:649-678`). Between the
validation pass and the `Repo.update` commit, a concurrent transaction
could mutate the chain in a way that creates a cycle through the
edited row. There is no DB-level constraint to catch this — Postgres
doesn't enforce acyclic self-FKs without a trigger or a recursive
CHECK.

Example race (A → B → C exists, two admins editing concurrently):
1. T1 begins, edits A, sets `parent_uuid = C`. Validator walks
   C → B → A — would hit `target == A`, so this is correctly
   rejected. OK.
2. T2 begins, edits C, sets `parent_uuid = A`. Validator walks
   A → nil — clean. T2 commits.
3. T1 retries the validation pass and now sees C → A → nil, no
   cycle, validates clean. T1 commits.
4. Final state: A → C → A (cycle).

The window is small (both transactions need to overlap on the same
chain) but the DB will accept the cycle and the in-memory tree walk
will then hit `@max_ancestor_depth 64` defensive cap, silently
truncating depth.

**Suggested fix:** Either (a) a `SELECT … FOR UPDATE` lock on the
proposed parent + the edited row inside an explicit transaction
wrapping the update, or (b) a recursive CTE check at update time
(more expensive but race-free), or (c) a Postgres trigger on
INSERT/UPDATE of `parent_uuid` that runs a CTE acyclicity check
and aborts. Option (c) is the strongest but adds a migration.

### A2 — MEDIUM — Two full-entity reads per DataForm mount

`assign_parent_options/4` (`data_form.ex:158-181`) calls
`EntityData.list_tree/2`, which calls `list_by_entity/2` and loads
*every* non-trashed row for the entity. Then `descendant_uuids/3`
calls `list_by_entity/2` *again* to walk the same set. For an entity
with 10k records, that's 20k row loads + ~80 KB transfer per form
mount. Mount runs twice (HTTP + WS), so it's 40k row loads per
form open in the worst case.

Two cheap fixes:
1. Hoist the `list_by_entity` call once, pass the result to both
   `list_tree`-style logic and `descendant_uuids` (refactor the
   public APIs to accept a pre-loaded `rows` arg).
2. Or wait until `handle_params/3` (Iron Law) — `mount/3` is the
   wrong place for any DB hit per **phoenix-thinking**, though the
   parent picker arguably needs the data before the first render
   for `selected={…}` to apply.

A bigger fix is to switch the picker to an autocomplete /
type-ahead with a paged query — necessary at the 10k+ scale, but
out of scope for this PR.

### B1 — LOW — Protocol-relative URL fallthrough in `safe_referer_path/2`

`safe_referer_path/2` (`entity_form_controller.ex:557-572`) returns
the parsed `path` straight through. If the Referer is
`https://yourhost.com//evil.com/foo`, `URI.parse/1` returns
`path: "//evil.com/foo"`. The same-host check passes (host is
`yourhost.com`), and the returned path is `"//evil.com/foo"`.

`Phoenix.Controller.redirect(conn, to: "//evil.com/foo")` then
raises `ArgumentError` via its `validate_local_url/1` guard
(Phoenix already rejects `//`-prefixed paths because browsers
interpret them as `https://evil.com/foo`). So this is **not** an
open redirect — Phoenix's guard catches it — but the controller
crashes with a 500 instead of falling back to `/`.

**Suggested fix:** add an explicit `String.starts_with?(path, "//")`
check (and `String.starts_with?(path, "/")` requirement) so the
fallback to `/` is graceful:

```elixir
%URI{scheme: scheme, host: ^expected_host, path: path}
when scheme in ["http", "https"] and is_binary(path) and
       byte_size(path) > 0 ->
  cond do
    String.starts_with?(path, "//") -> nil
    String.starts_with?(path, "/") -> reattach_query(path, referer)
    true -> nil
  end
```

### B2 — LOW — `internal_admin_path?/1` is too permissive

`internal_admin_path?/1` (`entity_form.ex:84-86`) uses
`String.contains?(path, "/admin")`. That matches `/admin-foo`,
`/some/admin-but-not-really`, `/x/admin.json`, etc. Should be
`String.contains?(path, "/admin/")` (with trailing slash) or
ideally `String.starts_with?(path, PhoenixKit.Utils.Routes.path("/admin"))`
so the URL prefix is honoured.

Practical impact: an internal page at `/admin-tools/foo` becomes
a valid "return target". Not exploitable (it's still a same-origin
path the user could have visited) but the function name implies a
stricter check than it performs.

### B3 — LOW — `URI.parse(referer)` called twice in the happy path

`safe_referer_path/2` (`entity_form_controller.ex:557-572`) calls
`URI.parse(referer)` in the head clause's match, then again inside
the body to pull `.query`. Two parses of the same string per
redirect. Cheap fix: bind the parsed URI once and pull both fields
from it:

```elixir
case URI.parse(referer) do
  %URI{scheme: scheme, host: ^expected_host, path: path, query: query}
  when scheme in ["http", "https"] and is_binary(path) ->
    if query, do: path <> "?" <> query, else: path
  _ ->
    nil
end
```

### B4 — LOW — Ancestor walk is N round-trips

`ancestor_chain_contains?/3` (`entity_data.ex:683-690`) issues one
`repo().get/2` per ancestor. For a 10-deep chain that's 10
sequential round-trips per validation pass. Fine for the typical
2–3 level case (admin UX), but a degenerate chain becomes
linearly slow. A recursive CTE collapses this to one query:

```sql
WITH RECURSIVE chain AS (
  SELECT uuid, parent_uuid, 0 AS depth FROM phoenix_kit_entity_data
    WHERE uuid = $1
  UNION ALL
  SELECT d.uuid, d.parent_uuid, c.depth + 1
    FROM phoenix_kit_entity_data d
    JOIN chain c ON d.uuid = c.parent_uuid
    WHERE c.depth < 64
)
SELECT 1 FROM chain WHERE uuid = $2 LIMIT 1;
```

Skip if the typical max depth is <5 and the form is mounted
infrequently.

### C1 — NIT — `list_tree/2` and `tree_order/1` are near-duplicates

`build_tree/3` in `entity_data.ex` (depth-tagged) and `tree_order/1`
in `data_navigator.ex` (returns `{records, depths_map}`) share the
same algorithm (group-by-parent + walk-from-roots + defensive
unknown-parent root promotion). The navigator version exists because
it needs the `record_depths` map keyed by uuid for template render-time
lookup, but the underlying walk could live in `EntityData` and the
navigator could derive the map from the `list_tree/2` output:

```elixir
flat = EntityData.list_tree(entity_uuid, opts)
records = Enum.map(flat, & &1.record)
depths = Map.new(flat, fn %{record: r, depth: d} -> {r.uuid, d} end)
```

DRY-up; not worth a follow-up commit on its own.

### C2 — NIT — Bulk-restore loses prior-status stash

`bulk_trash/2` and `bulk_restore/2` use `update_all` and bypass the
per-row metadata stash. Documented in F2's bullet ("Bulk paths are
unchanged; a bulk-trashed-then-restored row picks the `"draft"`
default") and intentional — but worth pinning with a test that asserts
the bulk-trashed-then-singly-restored case lands on `"draft"`, so a
later refactor doesn't accidentally extend the stash to bulk and
quietly re-publish a previously-archived row.

### C3 — NIT — Two identical parent-picker `<select>` blocks

`data_form.ex` renders the parent picker twice (multilang branch at
~L1436 and non-multilang branch at ~L1472). The two blocks are
byte-identical except for being inside different parent containers.
Standard `attr :parent_options` Phoenix function-component would
collapse to a single call site and prevent the two from drifting.
Same observation applies to other Record Settings cards in this file
— not a regression introduced by this PR, just an opportunity the
parent-picker work surfaces.

### C4 — NIT — `parent_uuid_error/1` duplicates `<.input>`'s error logic

`parent_uuid_error/1` and `translate_validator_error/1` in
`data_form.ex:343-360` re-implement the message-interpolation step
that `Phoenix.HTML.FormField` already does. The reason — the picker
is a raw `<select>` rather than `<.input type="select">` — is right,
but lifting the picker into `<.input>` (DaisyUI v5 `<.input>` supports
`type="select"` with `options:` and `prompt:`) would let the standard
`<:error>` slot do the work and delete both helpers.

---

## Test coverage

- **800 / 800 pass**, +10 from this PR (+15 pinning tests in
  `entity_data_parent_test.exs`, −5 from the bulk LV smoke
  consolidations in the dropdowns refactor).
- 77.29 % line coverage — at the upper end of the deeply-coupled-
  subsystem ceiling per the workspace `quality_sweep.md` playbook.
  Remaining gaps are defensive `rescue _ -> :ok` paths and
  Presence flows.
- No flaky-test signals in the PR description. 3× consecutive stable
  runs reported.

Coverage gaps I noticed worth flagging (none blocking):

- **The `:referenced_by_external` rescue in `delete/2`** (the new
  transaction-wrapped path) isn't exercised by a test that
  actually triggers a real Postgres FK violation. The existing
  `entity_data_trash_test.exs` tests assert the *function clause*
  via injected FK breakage, but none exercise the case where
  `has_live_children?` returns false and then the DB rejects the
  delete because of a concurrent insert. That branch is unreachable
  from a single-threaded test (`Ecto.Sandbox` serialises) — would
  need a dedicated concurrency test or a manual repro note.
- **The cycle race A1** has no test — by definition hard to write
  without a controlled-concurrency harness, but a comment in
  `validate_parent_not_descendant/1` flagging the race window
  would prevent a future contributor from assuming it's airtight.

---

## Style / convention

- **Phoenix-thinking Iron Law:** `mount/3` is mostly clean — the
  `_live_referer` capture is the only WS-only work, and it's
  correctly gated by `if connected?(socket)`. The parent-picker
  data load lives in `assign_parent_options/4` called from the
  shared hydrate path (which is invoked from `mount/3` rather than
  `handle_params/3`). Per the Iron Law, that DB hit should move to
  `handle_params/3`. Same comment applies to the existing hydrate
  pipeline; not a regression introduced here.
- **Ecto-thinking transaction boundaries:** `delete/2` and
  `bulk_delete/2` correctly wrap the precondition check + the
  destructive op in one transaction. The activity log call is
  correctly *outside* the transaction (so a log failure can't
  roll back the destructive op). Good pattern.
- **No GenServer or process used to "organise" anything.** The
  tree-building is plain data transforms over lists. ✅
- **`gettext/1` everywhere on user-facing strings.** ✅
- **`phx-disable-with` on every destructive action** — pinned by
  the LV tests via the menu-subtree regex match (which had to be
  refactored from the old direct attr-match because actions are
  now inside `<.table_row_menu>`). The new approach is solid.

---

## Verdict

**Approve with non-blocking follow-ups.** The Phase 2 re-validation
fixes are real (H1 is a genuine security fix, H2/H3 reclassify
errors usefully). The `parent_uuid` work is well-scoped and
well-tested. The "and Return" buttons and dropdowns overhaul are
straightforward UX wins that follow the existing workspace pattern.

The MEDIUM findings (A1 cycle race, A2 double-load) are scaling
concerns rather than correctness bugs in the typical
admin-UI-with-modest-record-counts case. The LOW findings are
mostly defensive-coding polish on already-correct code. The NITs
are clean-up opportunities.

Recommended order for the follow-up batch:

1. **B1** (protocol-relative graceful fallback) — one-line fix,
   prevents a class of crashes.
2. **B2** (`/admin/` with trailing slash) — one-line fix.
3. **A1** comment-flag at minimum, real fix deferred.
4. **A2** if entities with >1k records are in scope.
5. NITs as opportunistic cleanup.

---

## Skipped

- Behavioural verification of the dropdown / DnD interactions in
  a browser. The diff matches the canonical `<.table_row_menu>`
  shape used in `phoenix_kit_catalogue` / staff / settings;
  trusting the LV tests + author's "browser smoke verified locally"
  note.
- Migration audit — companion PR `phoenix_kit#538` ships V116
  (`parent_uuid` self-FK + index) and is reviewed there.
- `mix.lock` / dep update audit — addressed in the PR #14
  follow-up doc.
