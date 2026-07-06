# Follow-up Items for PR #21

Triaged against `main` on 2026-07-06 (post-merge, merge commit `37deb37`, with the
later `4f17704 "lib upgrades"` bump in effect).

## Resolved

### 1. Missing `@impl true` breaks the build — FIXED

`BUG - HIGH`. `sitemap_settings_schema/0` shipped without `@impl true`, but the
locked `phoenix_kit` (**1.7.175**) declares it as an `@optional_callbacks` entry
on the `Source` behaviour. With every sibling callback annotated, the compiler's
`@impl` consistency check turns the omission into a warning, and `mix precommit`
opens with `compile --force --warnings-as-errors` — so the gate was red on `main`.
The break only appeared after the post-merge `4f17704 "lib upgrades"` bumped core
to a version that declares the callback.

**Resolution:** `lib/phoenix_kit_entities/sitemap_source.ex` — added `@impl true`
and a doc note explaining it is safe (optional callback; core still gates the call
behind `function_exported?/3`). Compile under `--warnings-as-errors` now passes.

### 2. Empty-string global pattern collapses record URLs — FIXED

`BUG - MEDIUM`. `UrlResolver.get_global_pattern/1` treated any non-`nil`
`sitemap_entities_pattern` as a real pattern, unlike its sibling
`get_pattern_from_entity_settings/1` which guards `pattern != ""`. The new schema
declares `""` as this setting's default, so the admin UI can persist a blank
value; a persisted `""` on the global-tier fall-through path resolves to `""` and
emits the site root as every eligible record's `loc`.

**Resolution:** `lib/phoenix_kit_entities/url_resolver.ex` —
`get_global_pattern/1` now treats a blank string as unset
(`is_binary(pattern) and pattern != ""` → replace; `_` → `nil`), matching the
entity-settings guard. Added a locking test to
`test/phoenix_kit_entities/url_resolver_extras_test.exs`.

### 3. Moduledoc contradicted the `auto_pattern` default — FIXED

`IMPROVEMENT - MEDIUM`. The "Universal Entity Support" section and an example
comment stated `sitemap_entities_auto_pattern` is enabled by default; it is
`false` everywhere in code and in the new schema's help text. The wrong default is
security-relevant (auto-pattern on exposes internal/form entities).

**Resolution:** `lib/phoenix_kit_entities/sitemap_source.ex` — corrected both spots
to state the default is `false`/opt-in.

### 4. Customer domain in shipped admin help text — FIXED

`NITPICK`. The `sitemap_entities_include_index` help string named a specific
customer domain (`hydroforce.ee`), which would render in a public Hex package's
admin UI.

**Resolution:** `lib/phoenix_kit_entities/sitemap_source.ex` — replaced with a
generic sentence; the actionable guidance is preserved.

## Open

None.

## Validation note

This module is a library with no standalone DB in CI; integration tests
auto-exclude when Postgres is absent. In **this review environment** the `psql`
client is not installed, so `test/test_helper.exs` raises at load
(`System.cmd("psql", ["-lqt"], …)` → `:enoent`) and no tests — unit or
integration — could be executed here. This matches the PR #20 review environment.
The added test is tagged `:integration` (via `DataCase`) and runs wherever
`phoenix_kit_entities_test` exists.

The authoritative gate, `mix precommit`, was run against the change: compile
`--warnings-as-errors`, `deps.unlock --check-unused`, `hex.audit`,
`format --check-formatted`, `credo --strict`, and `dialyzer` (0 errors) all pass.

## Not changed (deliberate)

- The schema's `:integer` type in the `@spec` union (forward-compat), the
  omission of the per-entity name-keyed overrides, and the schema test's
  hardcoded defaults are all correct as written — see "Non-issues considered" in
  `CLAUDE_REVIEW.md`.
- No dependency-constraint bump in `mix.exs`. Adding `@impl true` is sound against
  the locked/released-against core; tightening `~> 1.7` to the minimum callback
  version would make it airtight but is out of this PR's scope.
