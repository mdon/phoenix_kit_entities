---
name: PR #14 follow-up — test_helper migration call swap
description: Resolution of CLAUDE_REVIEW.md findings for PR #14.
type: project
---

# PR #14 Follow-up — Swap test_helper to ensure_current/2

**Review:** [`CLAUDE_REVIEW.md`](./CLAUDE_REVIEW.md) (Claude Opus 4.7, 2026-05-05)
**Triage:** 2026-05-12

The post-merge review surfaced two non-blocking nits. Both were
resolved in the review pass itself — see `CLAUDE_REVIEW.md` →
`## Follow-up applied (2026-05-05)` for the original write-up. This
file is the canonical Phase-1 follow-up record per the workspace
playbook.

## Fixed (pre-existing)

- ~~**N1 (NIT)** — The inline comment in `test_helper.exs` pointed
  at `dev_docs/migration_cleanup.md`, a file that didn't exist in
  this repo. Replaced with a reference to the canonical write-up on
  `PhoenixKit.Migration.ensure_current/2` upstream — the docstring
  there covers the staleness story, clock-skew window,
  `schema_migrations` row accumulation, and prefix forwarding.~~ —
  `test/test_helper.exs:65-74`, resolved in the same review pass
- ~~**N2 (LOW)** — `mix.lock` pinned `phoenix_kit 1.7.103` which
  predated the published `PhoenixKit.Migration.ensure_current/2`
  (1.7.105+). `mix deps.update phoenix_kit` re-resolved the lock to
  1.7.105; the local lock is now at 1.7.106. `mix.exs` constraint
  left at `~> 1.7` rather than tightened to `>= 1.7.105` — relying on
  the lockfile for the floor matches the rest of the workspace.~~ —
  `mix.lock`, resolved in the same review pass

## Skipped (with rationale)

None. Both nits resolved.

## Files touched

| File | Change |
|---|---|
| `test/test_helper.exs` | N1 — comment retargeted to upstream docstring |
| `mix.lock` | N2 — `phoenix_kit` 1.7.103 → 1.7.106 (>= 1.7.105 required) |

## Verification

- `mix compile` — clean against the new lockfile;
  `PhoenixKit.Migration.ensure_current/2` resolves at runtime
- `mix test` — 791 / 791 pass (post-PR-#13-follow-up count)
- Stale-ref grep across `lib/` + `test/` — no remaining call sites
  of the deprecated `Ecto.Migrator.run([{0, PhoenixKit.Migration}], …)`
  shape

## Open

None.
