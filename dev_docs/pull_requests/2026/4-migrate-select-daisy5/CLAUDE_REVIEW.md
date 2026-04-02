# PR #4 Review — Migrate select elements to daisyUI 5 label wrapper

**Reviewer:** Claude
**Date:** 2026-04-02
**Verdict:** Approve

---

## Summary

Migrates all `<select>` elements in PhoenixKitEntities to the daisyUI 5 label wrapper pattern across 5 files: form builder, data form, data navigator, entities settings, and entity form. This is the largest of the module PRs with approximately 15 select elements covering status dropdowns, field type pickers, sort mode selects, security action selects, and import/export conflict strategy selects.

---

## What Works Well

1. **FormBuilder component updated.** The dynamic `select_field` component in `form_builder.ex` that generates selects from entity field definitions is correctly wrapped. This ensures all dynamically-generated entity data forms get the daisyUI 5 pattern.

2. **Duplicated status selects both updated.** The data form has two status select blocks (for different form modes) — both are consistently migrated.

3. **Complex entity form selects.** The field type select with `<optgroup>` elements is correctly wrapped. The security action selects with `phx-change` and `phx-value-*` attributes are properly handled.

4. **Settings import/export selects.** The entities settings page has selects for definition-level and record-level import actions — both are migrated with the wrapper placed correctly around the existing `<select>` with its `phx-change` and `phx-value-*` attributes.

---

## Issues and Observations

### Nit: Inconsistent label/select indentation in entities_settings.ex

In `entities_settings.ex`, the `<label class="select select-sm">` and closing `</label>` are placed outside the `<select>` block without matching indentation:

```heex
<label class="select select-sm">
<select
  ...
>
  ...
</select>
</label>
```

Other files in this PR indent the `<select>` inside the `<label>`. This is cosmetic only and doesn't affect functionality, but could be caught by `mix format`.

---

## Verdict

**Approve.** Comprehensive migration covering all entity module selects including the critical FormBuilder component.
