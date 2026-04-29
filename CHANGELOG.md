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
