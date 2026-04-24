# PR #8 Review — Finish entity-definition multilang + add locale-aware public URL helpers

**Reviewer:** Claude
**Date:** 2026-04-24
**Verdict:** Approve with follow-ups

---

## Summary

Bundles two related changes:

- **#6** — extracts `UrlResolver` from `SitemapSource` and adds `EntityData.public_path/3` / `public_url/3` so parent apps no longer hand-wire record URLs or drop the locale prefix.
- **#7** — dogfoods the entity-definition translation API across admin LiveViews and the sidebar (`list_entity_summaries/1` with `:lang`, per-locale ETS cache with match-delete invalidation, `entities_children/2` arity for future phoenix_kit core).

Extraction is clean, tests cover the important fallbacks (nil settings, malformed locales, path-traversal attempts, missing slugs, nil data maps), and `mix precommit` passes. The security guard in `safe_base_code/1` (strict `^[a-z]{2,3}$` allowlist before path interpolation) is the right call for a helper that takes caller-supplied locales.

---

## Findings

### 1. Phoenix iron law — DB queries in `mount/3` (pre-existing, not fixed here)

`lib/phoenix_kit_entities/web/entities.ex:27` and `lib/phoenix_kit_entities/web/data_navigator.ex:25` both call `Entities.list_entities(lang: locale)` in `mount/3`. Mount runs twice (HTTP + WebSocket), so every page load does this query twice. The PR added `lang:` to existing queries rather than moving them to `handle_params/3`. Not introduced here — worth flagging while the files are fresh.

**Suggested fix:** move the `list_entities` call into `handle_params/3`, set `entities: []` in `mount/3`.

### 2. Broad bare rescues in `UrlResolver`

`url_resolver.ex:187–197, 247–251, 330–334` use `rescue _ -> nil/default`. These swallow *any* error (compile errors, KeyError, etc.), not just DB unavailability. The PR body explains the intent ("Settings table unavailable, transient DB issues, misinstalled module") — narrowing to `DBConnection.ConnectionError` / `Postgrex.Error` and optionally guarding with `Code.ensure_loaded?(PhoenixKit.Settings)` would keep the defensive intent without hiding real bugs.

Style-level, not blocking.

### 3. Locale key-match brittleness in `resolve_summary_language/2`

`phoenix_kit_entities.ex:406–413` does `get_in(summary, [:settings, "translations", lang_code])` — exact string match. Translations are stored under whatever key `set_entity_translation` saw (typically the dialect form, e.g. `"es-ES"`). The sidebar caller passes `Gettext.get_locale(PhoenixKitWeb.Gettext)`, whose return format depends on parent-app Gettext configuration. If one side stores `"es-ES"` and the other queries with `"es"`, lookups silently miss and the sidebar shows primary-language labels.

Elsewhere the code normalizes via `Multilang.DialectMapper.extract_base`; this hot path skips it. Either normalize both sides or document explicitly that translation keys must match the Languages-module storage format exactly.

### 4. Catchall regex is permissive

`url_resolver.ex:100`: `^/:[a-z_]+/:[a-z_]+$` classifies *any* two-segment parameterized route as the entity catchall. An unrelated route like `/:category/:item` (e.g. a taxonomy URL) would be picked up and every entity would be rewritten onto it. This behavior pre-existed in `SitemapSource` but is now public-URL-facing via `public_path/3`, so the blast radius grew.

**Suggested fix:** require the second segment to be `:slug` or `:id` (`^/:[a-z_]+/:(slug|id)$`), or make catchall detection opt-in via a setting.

### 5. Translated-slug fallback produces duplicate URLs across locales

`entity_data.ex:1049–1054`: when no `_slug` override exists for a secondary locale, `public_path/3` builds `/es/products/<english-slug>`. The parent app's route handler will typically look up records by slug regardless of prefix, so both `/products/my-english-slug` and `/es/products/my-english-slug` serve successfully. The PR body calls translated slugs out as a follow-up.

For SEO, whoever ships this to production should emit `hreflang` alternates or a canonical tag — otherwise the duplicated URLs compete. Worth a helper alongside `public_path/3` before entity pages go live in production.

### 6. Minor — `@derive Jason.Encoder` on `EntityData` drops `entity_uuid`

`entity_data.ex:89–100`: if a consumer JSON-encodes a record and needs the FK, they'll be surprised. Pre-existing, not in PR scope — noting for future cleanup.

---

## Nits that are fine as-is

- `ActivityLog` guard with `Code.ensure_loaded?/1` + `try/rescue` is the right shape for an optional dependency.
- `entities_children/1` + `/2` arity backward-compat pattern is clean; comments document the migration path to `dynamic_children.(scope, locale)` in a future phoenix_kit core release.
- `build_routes_cache/0` + `:routes_cache` opt is a good perf pattern for listing pages; `SitemapSource` already uses it for the hot path.
- `invalidate_entities_cache/0` correctly match-deletes every per-locale entry (previously cleared only the single atom key, leaving stale per-locale rows behind).

---

## Recommended follow-ups

1. Move `list_entities(lang: locale)` out of `mount/3` in `Web.Entities` and `Web.DataNavigator` (Phoenix iron law).
2. Normalize locale keys for `settings["translations"]` lookups — or document the exact-match policy.
3. Tighten the catchall regex to require `:slug`/`:id` as the second segment, or gate catchall detection behind a setting.
4. Add `hreflang`/canonical helper alongside `public_path/3` before entity pages go live in production multilang sites.
5. Narrow the bare `rescue _` clauses in `UrlResolver` to the specific exception classes the defensive path is meant to cover.

---

## Verdict

**Approve with follow-ups.** Clean extraction, good security-conscious defaults, well-tested. Follow-ups are either pre-existing or scope-adjacent — none block merging.
