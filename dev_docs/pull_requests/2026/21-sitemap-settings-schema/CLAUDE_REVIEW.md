# PR #21 Review — `sitemap_settings_schema/0` on the entities sitemap source

**Reviewer:** Claude
**Date:** 2026-07-06
**Author:** Timujeen (`feat/sitemap-settings-schema`), merged as `828aee8` (merge `37deb37`)
**Verdict:** Approve with fixes (applied) — one of them unblocks a build broken at `main`

---

## Summary

The PR adds one optional callback, `sitemap_settings_schema/0`, to
`PhoenixKitEntities.SitemapSource`. It returns a fixed three-field schema so the
core Sitemap admin screen can render editors for the module-owned global
settings, and documents the split between the fixed set (surfaced to the UI) and
the per-entity, name-keyed overrides (kept console/Settings-only). A test locks
the schema shape and the three defaults. The design intent — ship a non-`@impl`
callback the core admin only calls behind `function_exported?/3`, so it is safe
against older `phoenix_kit` — is sound.

I verified the whitelist against the real source of truth. The three exposed
keys are exactly the module's **fixed** global settings and their declared
`default:` values match every runtime read:

| Schema key | Declared default | Runtime read | Match |
|---|---|---|---|
| `sitemap_entities_include_index` | `true` | `Settings.get_boolean_setting(_, true)` in `do_collect/1` and `sub_sitemaps/1` | ✅ |
| `sitemap_entities_auto_pattern` | `false` | `get_boolean_setting(_, false)` in `do_collect/1`, `get_fallback_pattern/1`, `entity_has_public_route?/2`, `UrlResolver.get_fallback_index_path/1` | ✅ |
| `sitemap_entities_pattern` | `""` (⇒ "unset") | no-default `get_setting/1` in `UrlResolver.get_global_pattern/1` | ⚠️ see finding #2 |

The two per-entity keys (`sitemap_entity_{name}_pattern`,
`sitemap_entity_{name}_index_path`) are correctly excluded — they are keyed by
entity name, not a fixed set. The core `sitemap_include_entities` toggle is also
correctly excluded (core owns it).

---

## Findings

### 1. BUG — HIGH: missing `@impl true` breaks `mix precommit` against the pinned core (fixed)

`lib/phoenix_kit_entities/sitemap_source.ex` — the PR shipped
`def sitemap_settings_schema` **without** `@impl true`, deliberately, reasoning
that older `phoenix_kit` never declares the callback. But the locked core is
**1.7.175**, whose `Source` behaviour already declares it:

```elixir
# deps/phoenix_kit/lib/modules/sitemap/sources/source.ex
@callback sitemap_settings_schema() :: [settings_field()]
@optional_callbacks [sitemap_filename: 0, sub_sitemaps: 1, sitemap_settings_schema: 0]
```

Every sibling callback in this module (`source_name/0`, `sitemap_filename/0`,
`sub_sitemaps/1`, `enabled?/0`, `collect/1`) is annotated `@impl true`, so the
compiler's `@impl` consistency check fires on the one that isn't:

```
warning: module attribute @impl was not set for function sitemap_settings_schema/0
callback (specified in PhoenixKit.Modules.Sitemap.Sources.Source). ...
Compilation failed due to warnings while using the --warnings-as-errors option
```

`mix precommit` starts with `compile --force --warnings-as-errors`, so **the gate
is red on `main`.** This wasn't caught at PR time because the post-merge
`4f17704 "lib upgrades"` commit is what bumped core to a version that declares
the callback — the missing annotation only became a warning afterward.

**Fix applied.** Added `@impl true`. It is correct against the locked core (the
callback exists and is optional) and the doc comment now records why it is safe.
The optional callback keeps the same runtime story: the core admin still gates
the call behind `function_exported?/3`, so releases predating the schema UI never
invoke it.

*Trade-off noted:* against a hypothetically older `~> 1.7` core that lacks the
callback, `@impl true` would emit a warning — but only a warning, and only if a
consumer compiled this package as a dep with `--warnings-as-errors` (deps compile
without it by default). A fresh `~> 1.7` resolve picks the latest core, which has
the callback. Given the package's own gate is the concrete break and the release
targets current core, `@impl true` is the right call. A later constraint bump to
the minimum core version that introduced the callback would make it airtight; out
of scope for this fix.

### 2. BUG — MEDIUM: empty-string global pattern collapses record URLs to the site root (fixed)

`lib/phoenix_kit_entities/url_resolver.ex` — `get_global_pattern/1` treated
**any** non-`nil` value of `sitemap_entities_pattern` as a real pattern:

```elixir
case safe_get_setting("sitemap_entities_pattern") do
  nil -> nil
  global_pattern -> String.replace(global_pattern, ":entity_name", entity.name)
end
```

Its sibling `get_pattern_from_entity_settings/1` guards `pattern != ""` — but this
one did not, so the two resolution paths were out of sync on the empty case. That
gap becomes reachable **because of this PR**: the new schema declares `""` as the
default for `sitemap_entities_pattern` (the test even documents `""` as the
"unset" representation for a string field), and the core admin page
"reads/writes each through `PhoenixKit.Settings` using its `key` and `default`" —
so a blank field can persist `""`.

Trace with a persisted `""` on an entity that falls through to the global tier
(no entity-settings pattern, no router match, no per-entity pattern):
`get_global_pattern` → `String.replace("", ":entity_name", name)` → `""`;
`get_url_pattern_cached` returns `""` (truthy in Elixir, so `||` short-circuits);
`effective_pattern = "" || fallback` → `""`; `build_path("", record)` → `""`;
`path = locale_prefix <> ""`; `build_url(path, base_url)` → the site root. Every
eligible record emits the homepage as its `loc` — a silently corrupt sitemap, not
a crash, and only on that fall-through path, hence MEDIUM.

**Fix applied.** `get_global_pattern/1` now treats a blank string as unset
(`is_binary(pattern) and pattern != "" -> …; _ -> nil`), mirroring the
entity-settings guard so both paths agree. Added a test —
*"treats a blank global sitemap_entities_pattern as unset (returns nil)"* — to
`url_resolver_extras_test.exs`.

### 3. IMPROVEMENT — MEDIUM: moduledoc contradicted the (now schema-documented) `auto_pattern` default (fixed)

`lib/phoenix_kit_entities/sitemap_source.ex` — the "Universal Entity Support"
section claimed *"By default, auto-pattern generation is enabled
(`sitemap_entities_auto_pattern: true`)"* and an example comment read
*"Auto-generated fallback (enabled by default)"*. The real default is `false`
everywhere in code (and in the new schema's own help text: *"Off by default"*).
This is not cosmetic: `auto_pattern` on makes **every** published entity eligible
via the `/:entity_name/:slug` fallback, including internal/form entities — the
docs told operators the risky mode was the default.

**Fix applied.** Corrected both spots to state the default is `false` (opt-in) and
that only routed/patterned entities are collected until it is enabled.

### 4. NITPICK: customer domain baked into shipped admin help text (fixed)

`sitemap_source.ex` — the `sitemap_entities_include_index` help string ended with
*"e.g. hydroforce.ee had to be switched this way before its entity index pages
showed up in the sitemap."* That renders a specific customer's domain into a
public Hex package's admin UI. Replaced with a generic, actionable sentence; the
useful guidance (what the toggle does, that it defaults on) is preserved.

---

## Non-issues considered

- **`:integer` in the `@spec` union with no entry using it** — intentional
  forward-compat for the field-descriptor type; not dead code in a spec.
- **Per-entity keys omitted from the schema** — correct; they are name-keyed, not
  a fixed set, and the moduledoc/`@doc` say so explicitly.
- **`function_exported?/3` gating in core** — verified in
  `deps/phoenix_kit/lib/modules/sitemap/sources/source.ex` (`get_settings_schema/1`)
  and `web/settings.ex`; the callback is genuinely optional at the call site.
- **Schema test hardcodes the three defaults** — acceptable; it pins the
  contract, and the table above cross-checks those defaults against the live reads.

---

## Validation

Authoritative gate: `mix precommit` = `compile --force --warnings-as-errors` +
`deps.unlock --check-unused` + `hex.audit` + `quality.ci`
(`format --check-formatted` + `credo --strict` + `dialyzer`).

- compile `--warnings-as-errors`: **now passes** (was failing on `main` — finding #1)
- `deps.unlock --check-unused`: clean
- `hex.audit`: no retired packages
- `format --check-formatted`: clean
- `credo --strict`: no issues (76 files)
- `dialyzer`: **0 errors** (`done (passed successfully)`)

Tests could not run in this environment — the `psql` client is not installed, so
`test/test_helper.exs` raises at load (`System.cmd("psql", …)` → `:enoent`),
identical to the PR #20 review environment. The added integration test is tagged
`:integration` (via `DataCase`) and runs wherever `phoenix_kit_entities_test`
exists. See FOLLOW_UP.md.
