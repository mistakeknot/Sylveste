---
name: cuj-verification
description: "Use when verifying critical user journeys in a running application without screenshots — queries structured /diag/ui/state endpoints for semantic UI state instead of visual inspection."
---

# interhelm:cuj-verification — Screenshot-Free User Journey Validation

## When to Use

Use when:
- Verifying a CUJ works correctly after code changes
- The application is a native app (Tauri, Electron) where browser DevTools aren't available
- Screenshot-based verification is too slow or token-expensive
- You need deterministic, parseable verification results

Do NOT use when:
- The application doesn't have a diagnostic server with `/diag/ui/state`
- Visual appearance (colors, layout, animations) is what needs verification
- The CUJ involves external system interactions (API calls, file system) not exposed via diagnostics

## The Pattern: State-Before → Action → State-After

Instead of taking screenshots to verify UI changes, query the structured UI state endpoint:

### Step 1: Capture state before action

```bash
app-diag ui  # GET /diag/ui/state
```

Record: `active_view`, panel states, selections, form values.

### Step 2: Perform the action

Execute the user action via the diagnostic server's `/control/*` endpoints. This pattern works for actions exposed through control endpoints (restart, reset, step, select, create). For actions that require UI interaction (button clicks, drag-and-drop), you'll need to add corresponding `/control/*` endpoints first — see the `runtime-diagnostics` skill for guidance on scaffolding control endpoints.

### Step 3: Capture state after action

```bash
app-diag ui  # GET /diag/ui/state again
```

### Step 4: Assert expected changes

Compare before and after states. Verify:
- Active view changed (if navigation was expected)
- Panel content updated (if data was expected to change)
- Selection state reflects the action
- Form values were processed
- No unexpected side effects (other panels/views shouldn't change)

## Example: Verifying "User selects an entity and views details"

```bash
# Step 1: Before state
app-diag ui
# → { "active_view": "world_map", "panels": { "inspector": { "visible": false } } }

# Step 2: Action — select entity via control endpoint
curl -X POST http://localhost:9876/control/select -d '{"entity_id": "country_42"}'

# Step 3: After state
app-diag ui
# → { "active_view": "world_map", "panels": { "inspector": { "visible": true, "selected_entity": "country_42" } } }

# Step 4: Assert
app-diag assert "panels.inspector.visible == true && panels.inspector.selected_entity == 'country_42'"
# → { "result": true }
```

**Token cost comparison:**
- Screenshot approach: ~1500 tokens per screenshot × 2 screenshots = ~3000 tokens
- Structured approach: ~200 tokens per JSON response × 2 responses = ~400 tokens
- **7.5x cheaper** per verification step

## Multi-Step CUJ Verification

For CUJs with multiple steps, chain state-before/action/state-after sequences:

```bash
# CUJ: "User creates a new entity and verifies it appears"

# Step 1: Verify entity list count before
app-diag assert "simulation.entity_count == 156"

# Step 2: Create entity via control
curl -X POST http://localhost:9876/control/create_entity -d '{"type": "country", "name": "NewCountry"}'

# Step 3: Verify entity count increased
app-diag assert "simulation.entity_count == 157"

# Step 4: Verify entity appears in UI
app-diag assert "panels.entity_list.items | contains('NewCountry')"

# Step 5: Select the new entity
curl -X POST http://localhost:9876/control/select -d '{"entity_name": "NewCountry"}'

# Step 6: Verify inspector shows the new entity
app-diag assert "panels.inspector.selected_entity.name == 'NewCountry'"
```

## When Screenshots Are Still Needed

Structured state queries don't replace screenshots for:
- **Visual regression testing** — colors, fonts, layout, alignment
- **Animation verification** — transitions, loading spinners
- **Responsive design** — viewport-dependent layout changes
- **Accessibility visual cues** — focus rings, contrast

Use interhelm for **functional** CUJ verification. Use screenshots for **visual** verification.
