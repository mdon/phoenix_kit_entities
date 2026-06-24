# PR #20 Review — Entities sitemap source auto-registration + per-language URLs

**Reviewer:** Claude
**Date:** 2026-06-24
**Author:** timujinne (`sitemap-entity-source`), merged as `aba8508`
**Verdict:** Approve with one fix (applied)

---

## Summary

Three related changes:

1. **Auto-registration** — `PhoenixKitEntities.sitemap_sources/0` returns
   `[PhoenixKitEntities.SitemapSource]`, so the core sitemap generator picks the
   source up via `PhoenixKit.ModuleRegistry.all_sitemap_sources/0` with zero host
   config. Verified the callback exists in `PhoenixKit.Module`
   (`deps/phoenix_kit/lib/phoenix_kit/module.ex:253`), is `defoverridable`, and
   the main module `use`s the behaviour — so the `@impl` compiles clean.

2. **Per-language emission** — `collect/1` and `sub_sitemaps/1` no longer
   short-circuit on the default language. They now run once per enabled language
   (the generator iterates languages) and emit a localized URL for a record only
   when that record actually carries a translation for the locale
   (`record_has_translation?/2`), avoiding 404 entries. Both gate on the new
   `include_entities?/0` (core `sitemap_include_entities` admin toggle, default
   true, falls open on DB hiccup).

3. **Per-entity opt-out** — `entity.settings["sitemap_exclude"] = true` keeps an
   entire entity out of the sitemap (`entity_sitemap_eligible?/2`), mirroring the
   existing per-record `metadata["sitemap_exclude"]` flag. This is the
   authoritative defense for internal/form entities whose records default to
   status `"published"` and would otherwise leak in once `auto_pattern` is on.

The threading of `language`/`is_default` through `collect_entity_entries` →
`collect_entity_records` → `do_collect_entity_records` and the
`prepend_index_entry` "skip localized index when no localized records" logic are
correct. Verified `UrlResolver.locale_prefix/2`, `DialectMapper.extract_base/1`,
`Multilang.multilang_data?/1`, and `Sitemap.include_entities?/0` all exist in the
pinned `phoenix_kit`. No duplicate-URL regression: default emits unprefixed,
non-default emits prefixed per-locale variants (intended hreflang behavior).

---

## Findings

### 1. BUG — MEDIUM: `record_has_translation?/2` false-positives on flat records whose field key collides with a locale code (fixed)

`lib/phoenix_kit_entities/sitemap_source.ex` — the original function treated
**every** top-level `record.data` key as a locale code:

```elixir
case record.data do
  %{} = data ->
    data
    |> Map.keys()
    |> Enum.reject(&(&1 == "_primary_language"))
    |> Enum.any?(fn key ->
      is_binary(key) and Languages.DialectMapper.extract_base(key) == base
    end)
  ...
```

That assumption only holds for **multilang** records, which are keyed by locale at
the top level (`%{"_primary_language" => ..., "en-US" => %{...}, "fr-FR" => %{...}}`).
A **flat** (single-language) record's `data` is keyed by **field names**
(`%{"title" => "...", "id" => "..."}`) — see `DEEP_DIVE.md` "JSONB Data
Structure". `DialectMapper.extract_base/1` just lowercases the segment before the
first `-`, so a field literally named like a base locale code collides:

- `extract_base("id")` → `"id"` (Indonesian) — **and `"id"` is an extremely common field key**
- `extract_base("no")` → `"no"` (Norwegian)
- `extract_base("it")` → `"it"` (Italian)

Consequence: on a site with such a language enabled as a **non-default** locale,
every flat record carrying the colliding field was reported as "having a
translation" and emitted a localized `/<locale>/…` URL — a page that 404s. That
is the exact failure mode this guard was added to prevent, so the bug quietly
defeats the PR's own goal. Not a crash and only fires for a specific
enabled-locale + field-key combination, hence MEDIUM rather than HIGH.

**Fix applied.** Gate on `Multilang.multilang_data?/1` (presence of the
`_primary_language` sentinel). Only multilang records are locale-keyed; a flat
record exists solely in the primary language and by definition has no
secondary-language translation, so it returns `false` on the non-default path
(it is still emitted on the default path via the `is_default or …` short-circuit
in `do_collect_entity_records/6`). The inaccurate "`record.data` is keyed by
locale" comment was corrected to describe both shapes.

### 2. IMPROVEMENT — MEDIUM: test gap on the new per-language behavior (fixed)

The PR's two new non-default tests (`collect/1`, `sub_sitemaps/1`) only assert the
**negative** case — field-keyed seed records yield no entries for `fr`. Neither
the collision bug above nor the **core new feature** (a genuinely-translated
record emitting a localized URL) was covered; deleting `record_has_translation?/2`
entirely would not have failed the suite for the positive direction.

**Fix applied.** Added two tests to the `collect/1` describe block:

- *"non-default language emits a record that has a real per-locale translation"* —
  seeds a multilang record (`_primary_language` + `en-US`/`fr-FR`) and asserts its
  slug appears under `language: "fr"` while the flat seed records do not. Locks in
  the feature and proves the fix does not over-correct.
- *"flat record with a locale-colliding field key is not emitted for that language"* —
  an entity with a field keyed `"id"`, a flat published record, queried with
  `language: "id"`; asserts the record is **not** emitted. Reproduces finding #1
  and locks the fix. (Asserts on the slug substring, so it does not depend on the
  test env's Languages/prefix configuration.)

### 3. NITPICK (in PR code): `include_entities?/0` used a fully-qualified nested-module call (fixed)

`credo --strict` flags `include_entities?/0` (added by this PR) at
`sitemap_source.ex` — `PhoenixKit.Modules.Sitemap.include_entities?()` is a
nested-module call that should be aliased ("Nested modules could be aliased at the
top of the invoking module"). Credo never caught it on the merged PR only because
the unrelated `:earmark` deps check (#4) aborted the gate first.

**Fix applied.** Added `alias PhoenixKit.Modules.Sitemap` and call
`Sitemap.include_entities?()`. (`Sitemap.RouteResolver` / `Sitemap.UrlEntry`
remain their own aliases — no conflict.)

---

## Non-issues considered

- `@impl PhoenixKit.Module def sitemap_sources` — no conflict with the
  `use`-injected default; it is `defoverridable`.
- `include_entities?/0` rescue-to-`true` — falls open only on DB/settings error;
  the off-toggle returns `false` normally. Preserves prior default behavior.
- `entity_excluded?/1` / `excluded?/1` on `nil` settings/metadata — the `_ ->
  false` catch-all handles `nil` (no crash).
- Removing the default-language gate does not double-emit: default = unprefixed,
  non-default = prefixed per-locale variants.

---

### 4. NITPICK (pre-existing, unrelated to this PR): orphaned `:earmark` in `mix.lock` (fixed)

`mix precommit` was already red on `main`: `deps.unlock --check-unused` reports
`:earmark` as locked but unreferenced (not in `mix.exs`). `git blame`/`git show`
trace it to the `af082ef "lib upgrades"` commit that rewrote `mix.lock`
(earmark → earmark_parser), leaving the old top-level `:earmark` lock behind. Not
introduced by PR #20, but it blocks the gate. Removed via `mix deps.unlock
earmark` (one-line `mix.lock` deletion) so the gate runs to completion. Flagged
here because it is out of PR scope.

### 5. NITPICK (in PR code): unreachable third clause of `record_has_translation?/2` (fixed)

`dialyzer` (`pattern_match_cov`) flagged the PR's third clause
`record_has_translation?(_record, _language) -> false` as dead: the second
argument's type across call sites is `nil | binary()`, which the `nil` and
`is_binary/1` clauses already cover completely. Latent in the PR (it shipped all
three clauses); only surfaced once the gate ran end-to-end. Also matches the
`elixir-thinking` guidance against `_ -> false` swallow-clauses.

**Fix applied.** Removed the dead clause. `record.data` being `nil` is still
handled (`Multilang.multilang_data?(nil) == false` → the flat branch returns
`false`).

## Validation

`mix precommit` (compile `--warnings-as-errors` + `deps.unlock --check-unused` +
`hex.audit` + format-check + `credo --strict` + dialyzer). The lib change compiles
clean under `--warnings-as-errors`. See FOLLOW_UP.md for the final recorded gate
result and the integration-test note for this environment.
