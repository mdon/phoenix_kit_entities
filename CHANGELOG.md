## 0.2.5 - 2026-06-08

### Added
- Env-gated path override for `phoenix_kit*` deps: `pk_dep/3` in `mix.exs` swaps the Hex pin for a local `path:` + `override: true` checkout when `<APP>_PATH` is set (e.g. `PHOENIX_KIT_PATH=../phoenix_kit mix test`), for cross-repo development. A blank/unset value falls back to the published pin, so `mix hex.publish` and CI resolve exactly as before. Documented under "Local cross-repo development" in `AGENTS.md`. (#19)

### Changed
- Dependency lockfile bumps: `phoenix_kit` 1.7.120 → 1.7.133, `etcher` 0.5.1 → 0.6.6, `fresco` 0.6.3 → 0.7.1, `oban` 2.22.1 → 2.23.0, `bandit` 1.11.1 → 1.12.0, `swoosh` 1.25.2 → 1.26.1, `tesla` 1.18.2 → 1.20.0, `req` 0.5.18 → 0.6.1, `igniter` 0.8.0 → 0.8.1, `phoenix_live_view` 1.1.30 → 1.1.31.

## 0.2.4 - 2026-05-25

### Fixed
- `PhoenixKitEntities.Web.Hooks.extract_ip/1` crashed with `Protocol.UndefinedError: protocol String.Chars not implemented for Tuple` on any non-4-tuple peer address — most commonly the IPv4-mapped IPv6 form `::ffff:a.b.c.d` that Docker bridge networks behind a reverse proxy emit. Because `extract_ip/1` runs inside `on_mount`, every entity LiveView entered a mount → crash → reconnect loop, leaving the admin Entities pages reconnecting forever. The address formatter now routes all tuples through `:inet.ntoa/1`, which handles both IPv4 4-tuples and IPv6 8-tuples and maps bad input to `"unknown"` instead of raising. (#17, #18)

### Changed
- Dependency lockfile bumps: `phoenix_kit` 1.7.116 → 1.7.120, `etcher` 0.4.6 → 0.5.1, `fresco` 0.5.4 → 0.6.3, `ex_doc` 0.40.2 → 0.40.3 (`ex_doc` is docs/dev-only).

## 0.2.3 - 2026-05-21

### Added
- `PhoenixKitEntities.UrlResolver.locale_prefix/2` — resolves the constant locale path-prefix (`"/en"`, `""`, …) for a `(language, is_default)` pair. Built for batch callers like sitemap generation: resolve once and prepend to many paths instead of re-reading the site-wide locale settings per URL.

### Changed
- `UrlResolver` now delegates to the framework-shared `phoenix_kit` core helpers instead of maintaining parallel copies: `build_path_with_language/3`'s prefix decision goes through `PhoenixKit.Modules.Sitemap.LocalePath.emit_prefix?/2` (the same policy core's own sitemap sources use), and the boot-safe primary-language check uses `PhoenixKit.Modules.Languages.prefixless_primary_safe?/0` (which also handles the mix-task context the previous local rescue missed). Behaviour-preserving.
- `SitemapSource` resolves the locale prefix once per generation in `do_collect/1` and `sub_sitemaps/1` and threads it through the entry builders, replacing the per-URL `(language, is_default)` arguments. The previous code called `build_path_with_language/3` per generated URL, each re-reading the site-wide locale settings via `PhoenixKit.Cache` (several serialized `GenServer.call`s) — roughly `4·N·L` lookups returning the same constant. The hot path is now a plain string prepend; per-generation settings lookups drop from O(N·L) to O(1).

### Fixed
- `EntityData.public_path/3` and `public_alternates/3` docstrings documented the pre-`default_language_no_prefix` behaviour ("primary language → no prefix") and shipped example URLs that were wrong under the default (setting OFF) — the primary language now gets the prefix (`/en/products/my-item`) unless the site-wide setting is ON. Prose and examples corrected. (These were illustrative, non-executed examples, so the suite was unaffected.)

## 0.2.2 - 2026-05-12

### Added
- `PhoenixKitEntities.EntityData.tree_from_rows/1` and `descendant_uuids_from_rows/2` — list-accepting variants of `list_tree/2` and `descendant_uuids/3`. Callers that need both shapes from one entity load (e.g. the parent picker) can now fetch rows once and feed both helpers instead of paying for the same `list_by_entity/2` call twice.
- Pinning test for the bulk-restore default-status contract — a row trashed via `bulk_trash/2` (no per-row metadata stash) restores to `"draft"`, not `"published"`. Guards against a future refactor accidentally re-publishing archived rows through the bulk path.

### Fixed
- `entity_form_controller.ex` `safe_referer_path/2` now explicitly rejects protocol-relative paths (`//evil.com/foo`). The same-host check already kept it from being an open redirect, but the raw `path` would bubble up to `Phoenix.Controller.redirect(to: …)` and trip its own `ArgumentError` guard with a 500. The fallback to `"/"` is now graceful. Same pass deduplicated the double `URI.parse(referer)` call by binding `query` in the URI match.
- `web/entity_form.ex` `internal_admin_path?/1` now requires `/admin/` (with trailing slash) and explicitly rejects `//`-prefixed paths. Previously `String.contains?(path, "/admin")` would also accept lookalikes like `/admin-tools/foo` and `/x/admin.json` as valid "and Return" targets.
- `web/data_form.ex` parent picker no longer loads the entity's row set twice — the previous call sequence to `EntityData.list_tree/2` followed by `EntityData.descendant_uuids/3` issued two full `list_by_entity/2` queries per mount. Now loads once and feeds both helpers.

### Changed
- `web/data_navigator.ex` `maybe_tree_order/4` delegates to `EntityData.tree_from_rows/1` instead of a near-duplicate local `tree_order/1` + `walk_for_navigator/3` implementation. Same defensive root-promotion behaviour, just from the shared source.
- Inline comment on `EntityData.validate_parent_not_descendant/1` documenting the validation-time race window (two concurrent edits on the same chain in opposite directions can each pass their own validator pass and then both commit, producing a cycle the DB will accept). Two fix paths sketched for a future PR — `pg_advisory_xact_lock` + per-row `FOR UPDATE` in the same txn, or a Postgres `BEFORE INSERT/UPDATE` trigger with a recursive-CTE acyclicity check (lives in the companion migration repo).

### Spec corrections
- `PhoenixKitEntities.get_mirror_settings/1` — spec claimed `%{definitions: boolean(), data: boolean()}` but the impl returns `%{mirror_definitions: …, mirror_data: …}`. Spec aligned with impl + docstring example.
- `PhoenixKitEntities.{enable,disable}_all_{definitions,data}_mirror/0` — four specs claimed `{non_neg_integer(), nil}` but the impl returns `{:ok, non_neg_integer()}`. Every caller already pattern-matches `{:ok, count}`. Specs corrected.

## 0.2.1 - 2026-05-05

### Changed
- Bump `phoenix_kit` lockfile from 1.7.103 → 1.7.105. The new release ships `PhoenixKit.Migration.ensure_current/2`, which `test/test_helper.exs` adopted in PR #14 as the re-runnable replacement for `Ecto.Migrator.run([{0, PhoenixKit.Migration}], :up, all: true)`. No production code path changed — test-suite-only impact.
- `test/test_helper.exs` — replaced a broken `dev_docs/migration_cleanup.md` doc pointer with a reference to the upstream `PhoenixKit.Migration.ensure_current/2` docstring (PR #14 review nit N1).

## 0.2.0 - 2026-05-04

### Added
- Soft-delete for `EntityData` (issue #12) — keeps rows alive when parent apps hold FK references (e.g. `orders.status_uuid` → `phoenix_kit_entity_data.uuid`). New status sentinel `"trashed"` joins the existing `{draft, published, archived}` set; no migration required.
- New public API on `PhoenixKitEntities.EntityData`: `trash/2`, `restore_from_trash/2`, `bulk_trash/2`, `bulk_restore_from_trash/2`, `list_trashed_by_entity/2`, `trashed_count/1`.
- `count_external_references/1` and `count_external_references/2` — reads `Application.get_env(:phoenix_kit_entities, :reverse_references, [])` (a list of `{entity_name, count_fn}` tuples) so parent apps can surface "used by N rows" hints. The 2-arity form takes a pre-loaded entity to skip the per-call preload when rendering many records. Informational only — not a delete-blocker.
- Three new error atoms in `PhoenixKitEntities.Errors`: `:already_trashed`, `:not_trashed`, `:referenced_by_external` with localized messages.
- DataNavigator admin UX: Trash filter view with count badge, per-row Restore-from-trash + Delete-forever buttons on trashed records, bulk-action bar branches by view (Archive/Restore/Trash on default views; Restore/Delete-forever on the Trash view).
- 130 net new tests — `entity_data_trash_test.exs` (49 tests) builds transient `_trash_test_parent` tables that mirror issue #12's exact `NOT NULL REFERENCES … ON DELETE RESTRICT` shape, exercising FK-violation paths against a real parent FK. New describe block in `data_navigator_live_test.exs` (18 tests) covers all event handlers + authorization + bulk-bar branching.
- AGENTS.md gained a "Soft-delete (trash) for EntityData" section documenting the parent-app FK motivation, public API, default-list filtering rules, slug uniqueness rationale, and the `:reverse_references` config hook.

### Changed
- `delete/2` and `bulk_delete/2` now catch `Ecto.ConstraintError` (foreign-key) and `Postgrex.Error` (SQLSTATE `23503` / `23502`) and return `{:error, :referenced_by_external}` instead of raising. The admin UI flashes a friendly message rather than a 500. **Soft return-shape change** — callers exhaustively pattern-matching `{:ok, _} | {:error, %Ecto.Changeset{}}` should add a clause for the new atom.
- Default-list queries (`list_all/1`, `list_by_entity/2`, `search_by_title/3`, `count_by_entity/2`) exclude trashed records by default. Pass `include_trashed: true` to opt in (admin trash views, reverse-reference checks). Mirror exporter inherits this exclusion — trashed records won't resurrect on re-export.
- `get_data_stats/1` now returns `trashed_records` separately; `total_records` reflects the visible (non-trashed) count.
- `get_by_slug/2` deliberately surfaces trashed rows so slug uniqueness is preserved across the trash bin.
- DataNavigator bulk Delete repurposed → soft-trash; permanent delete is a separate action available only from the Trash filter view.
- `toggle_status` cycle skips trashed (Restore is the only escape).
- `phx-disable-with` added to all 8 bulk-action buttons (3 from soft-delete additions + 5 pre-existing oversights).
- `entity_form_controller.ex` `private_or_local_ip?/1` swapped from `String.to_integer + rescue _` to `Integer.parse/1` with explicit `with`/`else` chain — pins `{int, ""}` so `"123abc"` no longer slips through as `123`.
- `sitemap_source.ex` `sub_sitemaps/1` `rescue _ -> nil` now logs the error inspect, matching the canonical pattern at the other two rescues in the file.
- `sitemap_source.ex` `enabled?/0` gained `catch :exit, _ -> false` to match the boot-resilience shape from `phoenix_kit_entities.ex` (sandbox-shutdown signals).
- `@spec` backfill on `list_trashed_by_entity/2` and `trashed_count/1`.

## 0.1.7 - 2026-05-02

### Changed
- `Web.Entities` reorder/archive/restore handlers now gate on `Scope.admin?` before any DB access — closes the missing-auth gap surfaced in PR #11 review.
- Card-view duplication in `Web.DataNavigator` collapsed via the `:draggable` attr on `<.draggable_list>` — ~80 lines removed.
- `position_update_query/2` raises `ArgumentError` on non-binary scope values (was silently fall-through).
- `ensure_manual_sort/1` logs at `Logger.error` and surfaces a warning flash when the sort-mode flip fails — admins now see the silent setting-flip outcome instead of the failure being swallowed.

### Added
- Audit row shape table in AGENTS.md documenting `actor_uuid` / `resource_uuid` / `metadata` conventions across entity and entity_data activity rows.
- Race-tolerance comment on `maybe_add_entity_position/1` documenting the concurrent-position-conflict resolution strategy.

## 0.1.6 - 2026-04-29

### Removed
- `PhoenixKitEntities.Migrations.V1` — dead code with zero callers in `lib/`, `test/`, or the host app. Entity tables are owned entirely by core PhoenixKit (`V17` creates them; `V40` / `V58` / `V67` / `V74` / `V81` evolve them). Host apps that were calling `Migrations.V1.up/1` directly should switch to `PhoenixKit.Migrations.up()`. **Note:** technically a breaking change for any standalone host that imported the V1 module, but in practice no known callers exist.
- `test/support/postgres/migrations/` — 210 lines of hand-rolled DDL deleted. Test schema now built by running core's versioned migrations directly via `Ecto.Migrator.run(TestRepo, [{0, PhoenixKit.Migration}], :up, ...)` — same call the host app makes in production. Schema drift between test and prod is now impossible by construction.

### Changed
- `Web.DataForm`, `Web.EntityForm`, `Web.EntitiesSettings` now defer DB queries from `mount/3` to `handle_params/3` — closes the still-open Phoenix iron-law follow-up from PR #9 across the remaining three admin LVs. All five admin LVs now compliant.
- `mount_data_form` / `mount_entity_form` / `mount_data_presence` / `mount_entity_presence` helpers renamed to `hydrate_*` to reflect that they fill data assigns rather than couple to the `mount/3` callback. `connected?(socket)` gating preserved exactly so presence still only initializes on the WebSocket pass.
- `entities_settings.ex`: 8-key settings map consolidated through a private `load_settings/0` helper, deduplicating the inline copy in `handle_event("save", ...)`.

### Fixed
- Test fixtures in `mirror/importer_test.exs` and `mix_tasks/import_test.exs` updated to match the real `phoenix_kit_users` schema: `account_type = 'person'` (was `'personal'`, which the production CHECK constraint rejects), `hashed_password` non-null, `inserted_at` / `updated_at` non-null. The previous hand-rolled test migration had been more permissive than production and was masking these latent bugs.

## 0.1.5 - 2026-04-28

### Fixed
- `entity_form_controller.ex`: replace `entity.id` with `entity.uuid` (lines 243 + 342) — primary key is `:uuid`, the previous reference would have crashed every public-form submission with `KeyError`
- `entity_form_controller.ex`: replace runtime-bound `logger.warning(...)` with `Logger.warning(...)` macro call — variable-bound macro dispatch raised `UndefinedFunctionError` on every `save_log` security flag

### Added
- `PhoenixKitEntities.Errors` module — central atom→message dispatcher for the 10 user-facing error categories surfaced by the admin LVs and public form
- Activity logging on every entity + entity_data CRUD path (create / update / delete / bulk operations / module toggle), with `actor_uuid` threaded from caller opts
- Public-form security hardening — X-Forwarded-For RFC1918 rejection (loopback / link-local / multicast / private-network octets), metadata size cap (`@metadata_string_cap 255`), browser/OS/device parsing
- `Mirror.Storage` filesystem path containment via `Path.expand` + boundary-prefix check
- Test infrastructure — `LiveCase`, `DataCase`, `Hooks`, test endpoint / router / layouts; supports the full LV admin smoke test suite
- 32 LiveView smoke tests across `Web.Entities`, `Web.EntityForm`, `Web.DataNavigator`, `Web.DataForm`, `Web.EntitiesSettings`
- Coverage push from 31.39% baseline to 75.14% across 5 quality batches (684 tests, 0 failures, 5/5 stable)

### Changed
- `Web.Entities` and `Web.DataNavigator` now defer DB queries from `mount/3` to `handle_params/3` — avoids the duplicate-query-on-mount Phoenix iron-law violation
- `ActivityLog` rescue shape canonicalised: `Postgrex.Error -> :ok`, `DBConnection.OwnershipError -> :ok`, fallback `error -> Logger.warning(...)`, `catch :exit, _ -> :ok`
- `Mirror.Storage` rescues narrowed from bare `rescue _` to `[ArgumentError, RuntimeError, FunctionClauseError]` for path operations
- `UrlResolver` rescues narrowed to a six-class DB-scoped list (no bare `_` catches)
- `FieldTypes.description_for/1` literal-clause helper introduced so gettext extraction works on all 12 type descriptions
- `handle_info` catch-alls promoted from silent ignore to `Logger.debug` across all 5 admin LVs
- `@spec` backfill on `routes.ex` (3 functions) and `sitemap_source.ex` (5 callbacks)
- `mix.exs` `test_coverage: [ignore_modules: [...]]` filter so coverage tracks production code, not test-support boilerplate

### Removed
- `PhoenixKitEntities.Web.DataView` — unrouted module with no callers anywhere in the workspace; verified via grep + ast-grep across `phoenix_kit_entities`, `phoenix_kit` core, and `phoenix_kit_parent`. Recoverable from git history if a public-display feature materialises later

## 0.1.4 - 2026-04-24

### Added
- `PhoenixKitEntities.UrlResolver` module — extracted URL pattern resolution and locale prefixing from `SitemapSource` into a shared helper
- `EntityData.public_path/3` and `public_url/3` — locale-aware public URL helpers with translated-slug support (`data[locale]["_slug"]`)
- `PhoenixKitEntities.list_entity_summaries/1` — lightweight sidebar query with `:lang` option
- `entities_children/2` arity on the sidebar callback for future phoenix_kit core releases that pass locale explicitly
- `PhoenixKitEntities.ActivityLog` — internal helper that logs entity and entity_data mutations through the optional `PhoenixKit.Activity` context
- README sections documenting multi-language support and public URL resolution
- Unit tests for `UrlResolver`, `public_path/3` / `public_url/3`, multilang field resolution, and per-locale sidebar cache invalidation

### Changed
- Admin LiveViews (`Web.Entities`, `Web.DataNavigator`, `Web.DataForm`) now thread the current locale through entity lookups so translated `display_name` / `display_name_plural` / `description` render in the admin UI
- Sidebar `entities_children` caches per-locale ETS entries; `invalidate_entities_cache/0` now match-deletes every locale variant instead of the single atom key
- `SitemapSource` delegates URL construction to `UrlResolver` while keeping its "prefix every language" policy
- `resolve_language/2` and `resolve_languages/2` are nil-safe so callers can pass an optional locale without a pre-check

## 0.1.3 - 2026-04-11

### Fixed
- Remove misleading Data View route override example (anti-pattern)
- Add routing anti-pattern warning to AGENTS.md
- Fix version mismatch between mix.exs and module function

## 0.1.2 - 2026-04-02

### Fixed
- Migrate select elements to daisyUI 5 label wrapper pattern
- Remove deprecated `select-bordered` class for daisyUI 5 compatibility

## 0.1.1 - 2026-04-01

### Fixed
- Fix compilation error: replace undefined `content_status_badge` with `status_badge` from PhoenixKit core components

## 0.1.0 - 2026-03-24

### Added
- Extract Entities module from PhoenixKit into standalone `phoenix_kit_entities` package
- Implement `PhoenixKit.Module` behaviour with all required callbacks
- Add `PhoenixKitEntities` schema for dynamic entity definitions with JSONB field schemas
- Add `PhoenixKitEntities.EntityData` schema for data records with JSONB field values
- Add `PhoenixKitEntities.FieldTypes` registry with 12 supported field types
- Add `PhoenixKitEntities.FormBuilder` for dynamic form generation and validation
- Add `PhoenixKitEntities.Events` PubSub helpers for entity/data lifecycle events
- Add `PhoenixKitEntities.Presence` and `PresenceHelpers` for collaborative editing with FIFO locking
- Add admin LiveViews: Entities, EntityForm, DataNavigator, DataForm, EntitiesSettings
- Add route module with `admin_routes/0`, `admin_locale_routes/0`, and public form routes
- Add `css_sources/0` for Tailwind CSS scanning support
- Add migration module (v1) with `IF NOT EXISTS` for both tables (run by parent app)
- Add public form component with honeypot, time-based validation, and rate limiting
- Add sitemap integration for published entity data
- Add filesystem mirroring (export/import) with mix tasks
- Add multi-language support (auto-enabled with 2+ languages)
- Add behaviour compliance test suite
- Add unit tests for changesets, field types, events, form validation, HTML sanitization, multilang
