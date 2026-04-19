---
artifact_type: canon
---

# Policy merge canon for auto-proceed authorization

This document defines the canonical policy merge behavior for authz evaluation.
It is the source of truth for layered policy composition used by `clavain-cli policy`
and gate wrappers.

## Inputs

- Global policy (`~/.clavain/policy.yaml`), optional.
- Project policy (`.clavain/policy.yaml`), optional.
- Environment overlay policy (`.clavain/policy.env.yaml`), optional.

## Merge rules

1. Inputs are merged in order: global → project → environment.
2. Rule matching is by operation (`op`), and the matching policy is first match in the merged rule list.
3. Rule list order is preserved while layering; the first matching rule in merged order wins.
4. `op: "*"` is terminal fallback and must be last effective catchall.
5. `vetted_within_minutes` and similar numeric limits merge by minimum.
6. Boolean `requires` keys merge with **AND** semantics by field and cannot be weakened by child policy unless explicitly allowed.
7. `mode` merges by authority precedence:
   - `force_auto` is strongest and always wins when explicitly set in child policy.
   - `block`/`auto`/`confirm` keep floor rules unless child policy can legally override with documented flags.
8. Non-monotonic changes from project policy require `allow_override: true` on parent rule:
   - lowering requirements or raising permissiveness is rejected.

## Worked examples

### Example 1 — Numeric minima apply across layers (`vetted_within_minutes`)

Global policy (`~/.clavain/policy.yaml`):

```yaml
version: 1
rules:
  - op: bead-close
    mode: auto
    requires:
      vetted_within_minutes: 60
```

Project policy (`.clavain/policy.yaml`):

```yaml
version: 1
rules:
  - op: bead-close
    requires:
      vetted_within_minutes: 30
```

Merged result:

- Rule match: `op: bead-close`
- Effective `vetted_within_minutes`: `30`
- Mode: `auto`

### Example 2 — Boolean AND rejects project lowering (`tests_passed`)

Global policy:

```yaml
version: 1
rules:
  - op: git-push-main
    mode: auto
    requires:
      tests_passed: true
```

Project policy:

```yaml
version: 1
rules:
  - op: git-push-main
    requires:
      tests_passed: false
```

Without `allow_override` on parent, merge is rejected:

- Result: `policy merge error`
- Reason: `tests_passed` cannot be relaxed from `true` to `false` for the same effective op.

If project intends to lower this requirement, parent must set:

```yaml
allow_override: true
```

### Example 3 — Catchall floor is not removable (`mode:*`)

Global policy:

```yaml
version: 1
rules:
  - op: "*"
    mode: confirm
```

Project policy:

```yaml
version: 1
rules:
  - op: "*"
    mode: auto
```

Merged result:

- Merge rejected.
- Reason: base `mode:"*" confirm` is a non-removable floor.
- Resolution: project cannot unilaterally raise default behavior unless global rule sets
  `allow_override: true`.

### Example 4 — `force_auto` escalates with warning

Global policy:

```yaml
version: 1
rules:
  - op: bead-close
    mode: auto
```

Project policy:

```yaml
version: 1
rules:
  - op: bead-close
    mode: force_auto
```

Merged result:

- Effective `mode`: `force_auto`
- `bead-close` is auto-confirmed with additional audit note.
- Logged warning: `policy override elevated auto behavior to force_auto`.

### Example 5 — First-match wins, catchall is terminal fallback

Global policy:

```yaml
version: 1
rules:
  - op: bead-close
    mode: block
  - op: bead-close
    mode: auto
  - op: "*"
    mode: confirm
```

Project policy:

```yaml
version: 1
rules:
  - op: "*"
    mode: block
```

Merged result for operation `bead-close`:

- First matching effective rule applies: `op: bead-close, mode: block` (global first entry).
- `bead-close` never reaches the second specific rule or catchall.
- Catchall remains terminal fallback only for operations that do not match earlier rules.

## Rejection summary

| Condition | Expected result |
|---|---|
| Child layer lowers required boolean guard without `allow_override` | Merge fails |
| Child layer raises mode from `block/confirm` to permissive mode without allowed parent override | Merge fails |
| Child layer introduces specific rule after fallback catchall that conflicts with stronger parent floor | Merge fails unless parent permits override |
| Unordered catchall (`"*"` not terminal after merge order) | Merge fails / lint warning |

