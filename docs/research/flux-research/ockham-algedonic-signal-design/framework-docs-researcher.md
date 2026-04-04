# SRE / Orchestration Tiered Alerting and Auto-Remediation: Framework Research

**Research question:** How do SRE frameworks and orchestration platforms implement tiered alerting and auto-remediation — specifically the boundary between "inform" and "act"?

**Date:** 2026-04-02
**Status:** Complete
**Ockham context:** Policy engine with dispatch-weight adjustment, authority-grant modification, theme freezing, and signal emission. Cannot directly kill or restart agents. All mappings below assume this constraint.

---

### Sources

**Google SRE:**
- [Error Budget Policy — SRE Workbook](https://sre.google/workbook/error-budget-policy/)
- [Alerting on SLOs — SRE Workbook](https://sre.google/workbook/alerting-on-slos/)
- [Embracing Risk — SRE Book](https://sre.google/sre-book/embracing-risk/)
- [SRE Error Budgets and Maintenance Windows — Google Cloud Blog](https://cloud.google.com/blog/products/management-tools/sre-error-budgets-and-maintenance-windows)

**Kubernetes:**
- [Liveness, Readiness and Startup Probes — kubernetes.io](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/)
- [Configure Probes — kubernetes.io](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Pod Lifecycle — kubernetes.io](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)

**PagerDuty:**
- [Escalation Policy Basics — PagerDuty Support](https://support.pagerduty.com/main/docs/escalation-policies)
- [Escalation Policies and Schedules — PagerDuty Support](https://support.pagerduty.com/main/docs/escalation-policies-and-schedules)

**Prometheus:**
- [Alerting Rules — Prometheus Docs](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/)
- [Alerting on SLOs — SRE Workbook](https://sre.google/workbook/alerting-on-slos/)
- [Alerting Best Practices — AWS Managed Prometheus Blog](https://aws.amazon.com/blogs/mt/alerting-best-practices-with-amazon-managed-service-for-prometheus/)

**Circuit Breakers:**
- [CircuitBreaker — Resilience4j Docs](https://resilience4j.readme.io/docs/circuitbreaker)
- [Circuit Breaking — Envoy Proxy Docs](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/upstream/circuit_breaking)
- [Circuit Breaker — Azure Architecture Center](https://learn.microsoft.com/en-us/azure/architecture/patterns/circuit-breaker)
- [Circuit Breaker — Martin Fowler](https://martinfowler.com/bliki/CircuitBreaker.html)

**Internal prior art:**
- `/home/mk/projects/Sylveste/docs/research/flux-research/authority-tiers/synthesis.md` — ceiling model, demotion asymmetry, evidence thresholds
- `/home/mk/projects/Sylveste/docs/research/flux-research/cuj-gating-model/synthesis.md` — three-state gates, compound false-block cost, adaptive switching

---

### Findings

## 1. Google SRE Error Budgets: The Inform / Act Boundary

### What the Policy Says

Google's error budget policy is a published governance document (the SRE Workbook includes a worked example for a game service). The policy defines three automatic trigger levels:

| Trigger | Threshold | Action |
|---------|-----------|--------|
| Budget exhaustion | 100% of 4-week budget consumed | Release freeze (all changes except P0 + security fixes) |
| Single incident spike | 20% of budget consumed in one incident | Mandatory postmortem with at least one P0 action item |
| Recurring problem | 20% consumed by same outage class in one quarter | P0 quarterly planning item |

### Key Structural Finding: Engineering Judgment, Not Automatic Rollback

The Google policy does **not** specify automatic traffic drain or rollback. The response to budget exhaustion is a **governance action** (freeze), not a mechanical action (rollback). Automated rollback is delegated to deployment tooling (Argo, canary systems) at the deployment layer, not the SRE policy layer. CTO arbitration resolves disagreements.

### Multi-Window Burn Rate Alerting: The Inform Gradient

The SRE Workbook's alerting-on-SLOs chapter formalizes the gradient from "inform" to "urgent page" using burn rate multipliers across paired time windows:

| Tier | Long Window | Short Window | Burn Rate | Budget Impact | Response |
|------|------------|--------------|-----------|---------------|----------|
| Page (urgent) | 1 hour | 5 minutes | 14.4x | 2% in 1h | Immediate human |
| Page (significant) | 6 hours | 30 minutes | 6x | 5% in 6h | Immediate human |
| Ticket (scheduled) | 3 days | 6 hours | 1x | 10% in 3d | Next business day |
| Silence | — | — | <1x | Negligible | No action |

**Both windows must breach simultaneously** to fire the alert. The short window suppresses transient spikes; the long window suppresses slow drift that recovers before it matters.

**The mathematical basis:** `budget_consumed = (burn_rate × window_duration) / reporting_period`. A 14.4x burn rate over 1 hour on a 30-day SLO consumes exactly 2% of the monthly budget. This is the minimum signal worth a page — not "something is on fire" (that requires separate liveness signals) but "at this rate, we exhaust budget in ~50 hours."

### Ockham Mapping

The burn-rate model maps directly to Ockham algedonic signals:

- **Ticket-tier burn** (1x, 10% over 3d) → `ADVISORY` signal; Ockham adjusts dispatch weights downward (increase oversight), does not freeze
- **Page-tier burn** (6x, 5% over 6h) → `WARNING` signal; Ockham freezes new theme grants for the affected domain, emits signal for UI
- **4-week budget exhausted** → `CRITICAL` signal; Ockham revokes Execute+ authority grants in domain, emits halt signal to human
- **20% spike in single incident** → `INCIDENT` signal; Ockham drops domain to Propose-only until human re-grants

The "both windows must breach" requirement is a direct analogue for Ockham's two-signal confirmation design: a single bad observation should not trigger irreversible authority revocation.

---

## 2. Kubernetes Probes: Three Response Levels by Failure Kind

### The Decision Framework

Kubernetes models three distinct probe failure semantics, each with a different response:

| Probe | When Used | Failure Action | Reversible? |
|-------|-----------|----------------|-------------|
| **Startup** | Slow-starting containers | Kill + restart (applies restart policy) | Yes (restart policy controls) |
| **Liveness** | Deadlock / hung process | Kill + restart | Yes |
| **Readiness** | Temporarily overloaded / dependent-service-down | Remove from EndpointSlice (stop routing) | Yes — automatic on recovery |

**The fundamental design principle:** readiness affects routing, liveness affects process lifecycle. These are orthogonal decisions deliberately separated.

### Failure Threshold Mechanics

```
Total failure detection time = failureThreshold × periodSeconds
```

A common pattern sets liveness `failureThreshold` higher than readiness to ensure a pod is observed "not ready" for a window before it is hard-killed. This introduces a graduated response: traffic is drained before the restart, preventing simultaneous traffic-loss-plus-restart from compounding.

Startup probes gate all other probes. Until startup succeeds, neither liveness nor readiness runs — this prevents false-positive kills during initialization.

### Known Failure Modes

**Liveness probe misconfiguration** (the most dangerous failure mode): If a liveness probe fires on transient failures (memory pressure, slow GC, external dependency latency), it triggers a restart cascade. A restarting pod is unavailable; multiple pods restarting simultaneously causes a service outage from a probe that was trying to prevent one. The anti-pattern is using liveness to check external dependency health.

**Readiness probe overreach**: If readiness probes check deep dependencies (database reachable, cache warm), a dependency outage pulls all pods from all load balancers simultaneously. The anti-pattern is coupling pod readiness to external system health.

**Startup probe missing**: Without a startup probe, a slow-starting application looks like a liveness failure during initialization, causing kill-before-ready loops.

### Ockham Mapping

The readiness/liveness split maps cleanly to Ockham's two available levers:

- **Readiness equivalent** = `dispatch_weight = 0` for an agent class: traffic stops routing to that agent, but the agent is not killed. Used for temporarily degraded performance, dependency issues, or elevated error rates. Reversible on recovery signal.
- **Liveness equivalent** = authority revocation: the agent cannot claim new work. Used for detected deadlock patterns, repeated policy violations, or sustained budget exhaustion. Requires re-grant to recover (explicit human action, not automatic).
- **Startup equivalent** = shadow mode gate: new agent classes operate with `mode: shadow` until proving N successful executions, then receive their first Execute grant. This prevents premature authority grant to unproven agents.

The K8s lesson: separate "stop sending work" from "revoke authority to work." These should trigger at different thresholds and recover independently.

---

## 3. PagerDuty Escalation: Tiered Acknowledgment with Anti-Fatigue Controls

### Tier Structure

PagerDuty's escalation policies are ladder structures: if no acknowledgment within the timeout, escalate to the next rule. The escalation mechanics:

| Parameter | Default | Range |
|-----------|---------|-------|
| Escalation timeout (single target) | 30 min | 1 min minimum |
| Escalation timeout (multiple targets same rule) | 30 min | 3 min minimum |
| Maximum policy repetitions | 9 loops | — |

**Critical mechanic:** An incident does not escalate if acknowledged or resolved before the timeout. The escalation ladder is a fallback path, not a notification broadcast. Multiple users on the same rule receive simultaneous notifications.

**Urgency differentiation:** High-urgency incidents (pages) trigger aggressive multi-channel notification (phone, SMS, push, email). Low-urgency incidents can be configured to use quiet channels only (email, push) — or no notification at all, waiting for human inspection. This is the core anti-fatigue mechanism: not all signals deserve the same interrupt cost.

### Anti-Fatigue Architecture

PagerDuty's best-practice model uses **three distinct tiers at internal PagerDuty**:

- **Tier 1 (notify):** Page on-call engineer. Quiet channels for low urgency, aggressive for high.
- **Tier 2 (escalate):** If unacknowledged after timeout, escalate to secondary on-call or team lead.
- **Tier 3 (bridge):** Conference bridge or incident commander for critical, long-duration, or multi-team incidents.

The bridge tier is not triggered automatically by the escalation policy alone — it is initiated by the incident commander after human assessment of impact.

**The inform/act boundary in PagerDuty:** The escalation policy is pure inform until a human acts (acknowledges, resolves, or initiates a bridge). The policy engine has no automatic remediation capability — it is a notification routing system. Actual remediation is external (runbooks, tools, humans).

### Ockham Mapping

Ockham can implement the PagerDuty pattern more directly than PagerDuty can, because Ockham can *act* on signals, not just route notifications:

- **Tier 1 (notify):** Emit algedonic signal to UI dashboard. No authority change. Dispatch weights unmodified.
- **Tier 2 (weight adjustment):** After signal persists for N minutes unaddressed, reduce dispatch weights for the flagged domain by X%. This is the readiness-drain equivalent — work still routes there, but at lower priority.
- **Tier 3 (authority freeze):** After weight adjustment persists for M minutes, freeze new theme grants. Agents in-flight complete; no new dispatch into domain.
- **Tier 4 (human required):** Revoke Execute+ authority. Human re-grant required. This is the PagerDuty "bridge call" equivalent — an irreversible escalation that requires human acknowledgment to resolve.

The timeout/repetition mechanics map to Ockham's persistence windows: a signal that fires once and resolves should not advance the escalation ladder. A signal that persists at T1 for 30 minutes without acknowledgment should auto-advance to T2.

---

## 4. Prometheus Alerting: Suppression and Routing Mechanics

### The `for` Clause: Transient Suppression

The `for` clause in an alerting rule requires the condition to be continuously true for the specified duration before the alert fires. This suppresses transients:

```yaml
- alert: HighErrorRate
  expr: job:request_error_rate:ratio5m > 0.05
  for: 10m       # Must hold for 10 minutes, not just one scrape
  labels:
    severity: warning
```

Between first evaluation and the `for` duration, the alert is in `pending` state — visible in dashboards but not routed to notification. Only after it transitions to `firing` does Alertmanager route it. This is the Prometheus equivalent of the "both windows must breach" requirement from the multi-window burn rate model.

### Severity Labels and Routing Trees

The canonical severity ladder in mature Prometheus setups:

| Label | Meaning | Routing |
|-------|---------|---------|
| `info` | Noteworthy, not urgent | Ticket / email |
| `warning` | Degraded but not down | Slack channel, ticket |
| `critical` | Service impaired, SLO at risk | Page on-call |
| `page` | Severe, immediate action required | PagerDuty / high-urgency page |

Alertmanager routes through a tree. Each node can match on labels and apply grouping, inhibition, and receiver configuration. Inhibition rules prevent low-severity alerts from firing when a high-severity alert already covers the same service — this is the primary anti-flooding mechanism.

### Alert Fatigue Prevention: The Four Structural Controls

1. **`for` duration** — suppresses transients and flapping. The minimum meaningful duration is at least one SLO evaluation period.
2. **Inhibition rules** — when a critical alert fires, suppress warning and info alerts for the same service. Prevents alert storm from a single root cause.
3. **Grouping** — Alertmanager batches related alerts into single notifications. A routing tree with `group_by: [service, severity]` sends one notification per service-severity pair per interval, not one per individual alert.
4. **`group_wait` and `group_interval`** — Controls the initial delay before sending a notification (for grouping) and the interval between repeated notifications (for ongoing incidents). Prevents batching delay from hiding immediate crises while preventing repeat-spam.

### Ockham Mapping

The Prometheus model provides the cleanest direct analogue for Ockham signal design:

- **`for` duration** maps to Ockham's persistence window before escalating to the next tier. A signal that recovers within its persistence window should not advance the ladder.
- **Inhibition rules** map to Ockham's signal suppression when a domain is already in a high-severity state. If Execute authority is already revoked, a new warning about the same domain should not re-trigger the notification pipeline.
- **Grouping** maps to Ockham's aggregation across agents in the same domain: if five agents in `core/intercore/` all show degraded success rates simultaneously, that is one signal about the domain, not five signals about individual agents.
- **Severity labels** map directly to Ockham's signal severity taxonomy (see Tier mapping in section 1 above).

---

## 5. Circuit Breakers: State Machine with Hysteresis

### The Core State Machine (Resilience4j as canonical implementation)

```
CLOSED ──[failure_rate ≥ threshold]──→ OPEN
OPEN ──[waitDurationInOpenState elapsed]──→ HALF_OPEN
HALF_OPEN ──[failure_rate < threshold on N probes]──→ CLOSED
HALF_OPEN ──[failure_rate ≥ threshold]──→ OPEN
```

**Default configuration (Resilience4j):**

| Parameter | Default | Role |
|-----------|---------|------|
| `failureRateThreshold` | 50% | CLOSED → OPEN trigger |
| `slowCallRateThreshold` | 100% | Slow-call-based OPEN trigger |
| `slowCallDurationThreshold` | 60,000ms | What counts as "slow" |
| `waitDurationInOpenState` | 60,000ms | How long before HALF_OPEN probe |
| `permittedNumberOfCallsInHalfOpenState` | 10 | Probe sample size |
| `slidingWindowSize` | 100 | N for COUNT_BASED window |
| `minimumNumberOfCalls` | 100 | Min observations before OPEN allowed |
| `automaticTransitionFromOpenToHalfOpenEnabled` | false | Must be manually triggered or timer-based |

**The hysteresis principle:** The circuit does not close on a single success — it requires `permittedNumberOfCallsInHalfOpenState` probes that meet the threshold. This prevents premature close after a single lucky call during a still-degraded backend.

**Hystrix vs Resilience4j difference:** Hystrix used a single probe call in HALF_OPEN; Resilience4j uses a configurable sample. This is a direct recognition that single-probe recovery detection is too noisy.

### Envoy: Network-Layer Circuit Breaking (Different Model)

Envoy implements circuit breaking at the proxy layer, not the application layer. This is architecturally different:

- **No HALF_OPEN state machine** — Envoy uses resource limits (max connections, max pending requests, max concurrent requests, max retries) rather than failure rate thresholds
- **No recovery probing** — when limits are released (load drops), traffic resumes automatically
- **Retry budgets** — Envoy caps total retry volume as a percentage of normal request volume, preventing retry storms from amplifying failures

When a circuit breaker triggers on HTTP requests, Envoy sets the `x-envoy-overloaded` header, signaling downstream systems. This is an observation signal, not an action signal — downstream must decide what to do with it.

**The key insight from Envoy:** A resource-capacity model (queues fill → reject) is simpler than a failure-rate state machine and composes better with load balancing. It does not distinguish "backend is down" from "backend is temporarily overloaded" — it simply enforces capacity limits.

### Backoff Strategy for HALF_OPEN Probe Timing

Once a circuit opens, the question is when to probe again. The standard approaches:

1. **Fixed wait (Resilience4j default):** `waitDurationInOpenState = 60s`. Simple; may be too slow for fast-recovering backends or too fast for systemic failures.
2. **Exponential backoff with jitter:** Wait doubles on each OPEN → HALF_OPEN → OPEN cycle. Adds random jitter to prevent thundering-herd when many circuit breakers reset simultaneously (all services probing the same backend at t+60s).
3. **Envoy's jittered exponential:** Base interval 25ms, max 250ms (10x cap), fully jittered. Used for retries, not circuit state transitions.

### Ockham Mapping

The circuit breaker state machine maps directly to Ockham's authority tier model:

| Circuit State | Ockham Authority State | Recovery Mechanism |
|---------------|----------------------|--------------------|
| CLOSED | Execute+ granted | Normal operation |
| OPEN | Authority frozen / weight = 0 | Wait for `waitDuration`, then probe |
| HALF_OPEN | Execute on N-probe shadow mode | N successes required to restore full grants |

The Resilience4j `minimumNumberOfCalls` (100 minimum before OPEN is allowed) maps to the authority-tiers synthesis `n_min` requirement (5-50 successful executions before promotion is eligible). Both prevent triggering based on statistically insignificant samples.

**The HALF_OPEN → CLOSED recovery parallels the authority demotion asymmetry** from the authority-tiers synthesis:
- Promotion to Execute requires 5 successes + 3 consecutive + 1 day (conservative)
- Recovery from OPEN to CLOSED requires 10 probes below threshold (deliberate probe, not passive observation)
- Both are designed to be harder to achieve than to lose — asymmetric by design

**The Envoy model** (resource limits, not failure-rate state machines) applies to Ockham's dispatch capacity layer: if the dispatch queue for a domain exceeds a threshold (too many in-flight agents), new dispatch into that domain is rate-limited. This is not a quality signal — it is a capacity signal. The two should be separate levers.

---

### Findings Summary: The Inform/Act Boundary

Across all five frameworks, the inform/act boundary follows a consistent pattern:

**The boundary is not a single threshold. It is a gradient with deliberate persistence requirements at each tier.**

| Tier | Framework Analog | Signal Kind | Ockham Action |
|------|-----------------|-------------|---------------|
| 0: Observe | Prometheus `info` / Ticket-burn | Single metric exceeds threshold | Emit signal to dashboard, no authority change |
| 1: Warn | Prometheus `warning` / 6h burn | Sustained degradation (for duration) | Reduce dispatch weights, emit WARNING signal |
| 2: Degrade | K8s readiness fail / Circuit HALF_OPEN | Repeated failures exceed threshold | Freeze new theme grants, increase oversight ratio |
| 3: Freeze | K8s readiness drain / PD Tier 2 | Persistent degradation, unacknowledged | `dispatch_weight = 0` for domain, emit CRITICAL signal |
| 4: Revoke | Budget exhausted / Circuit OPEN | Sustained failure requiring human judgment | Revoke Execute+ authority; human re-grant required |

**The three structural controls that appear in all five frameworks:**

1. **Persistence window before action** — `for` duration (Prometheus), `failureThreshold × periodSeconds` (K8s), `waitDurationInOpenState` (Resilience4j). A condition must persist for a window before the next tier triggers. Prevents transient spikes from causing irreversible actions.

2. **Asymmetric recovery** — Harder to recover than to lose. Resilience4j requires N probes, not one. PagerDuty requires acknowledgment, not just signal-quiet. Authority tiers require N successes + consecutive + days. Recovery is a deliberate act, not automatic reversal.

3. **Inhibition / suppression** — Prometheus inhibition rules, K8s startup probe (gates others), PagerDuty low-urgency quiet channels. A higher-tier alert active in a domain suppresses lower-tier noise from the same domain. Prevents flooding while one alarm is already ringing.

**What Ockham can do that these frameworks cannot:**

All five frameworks operate on binary signals (up/down, pass/fail, over-threshold/under-threshold). Ockham operates on **authority grants and dispatch weights**, which are continuous. This enables graduated responses that these frameworks approximate with discrete tiers:

- Dispatch weight: 0.0 → 1.0 (continuous degradation, not binary stop/go)
- Authority confidence decay (exponential, not sudden revoke)
- Domain-scoped action (affect only the degraded domain, not the entire agent)

The circuit breaker hysteresis band (promote at 90%, demote at 75%) from authority-tiers synthesis is exactly the structural pattern that Resilience4j uses for HALF_OPEN → CLOSED (require N probes below 50% failure before closing). The terminology differs; the mechanism is identical.

---

### Confidence

| Finding | Confidence | Basis |
|---------|------------|-------|
| Google SRE does not automate rollback at the policy layer | High | Direct from SRE Workbook error-budget-policy page; rollback is deployment-layer concern |
| Multi-window burn rate thresholds (14.4x/6x/1x) | High | Direct from SRE Workbook alerting-on-slos; mathematically derived |
| K8s readiness = stop routing, liveness = restart | High | Direct from kubernetes.io official docs |
| Liveness misconfiguration → cascading restarts (anti-pattern) | High | Documented in official K8s guidance, confirmed by multiple sources |
| PagerDuty escalation is pure-inform until human acts | High | Direct from official support docs |
| Resilience4j default parameters | High | Direct from official Resilience4j docs (v3) |
| Envoy uses resource-limit model, not failure-rate state machine | High | Direct from Envoy architecture docs |
| Prometheus `for` + inhibition + grouping as four-control anti-fatigue model | High | Synthesized from official Prometheus docs + AWS managed Prometheus blog |
| Ockham tier mappings | Medium | Structural analogy; exact thresholds require empirical tuning |

---

### Gaps

1. **No published data on circuit breaker parameters for AI agent workloads.** All parameters (50% failure rate threshold, 60s wait, 10 probes) are derived from synchronous RPC workloads. AI agent tasks are long-duration, non-idempotent, and expensive to abort mid-flight. The appropriate `failureRateThreshold` and `waitDurationInOpenState` for agent dispatch is an open design question.

2. **PagerDuty escalation timeouts are response-latency-tuned, not consequence-tuned.** The 30-minute default timeout assumes a human who may be asleep. Ockham's equivalent timeouts should be tuned to the consequence of the action at each tier, not to human response latency. The right persistence window for "revoke Execute authority" is different from "reduce dispatch weight."

3. **Envoy's `x-envoy-overloaded` header has no Ockham equivalent signal path.** Envoy signals capacity pressure to downstream callers; Ockham currently has no standardized signal for "domain is capacity-constrained" vs "domain is quality-degraded." These warrant separate signal types.

4. **Multi-window burn rate requires a continuous success-rate time series.** Ockham tracks outcomes per bead, not per time window. Building the equivalent of Prometheus's 1h and 5m windows requires either a streaming rate computation or a periodic batch query over recent bead completions. The storage model (Dolt per-bead records vs. time-series) is an implementation gap.

5. **No studied interaction between authority-tier demotion and circuit breaker state.** When an agent's authority is revoked (circuit OPEN), its in-flight work should complete, not be aborted. The ordering of "freeze new dispatch" vs "terminate current work" needs explicit protocol definition; none of the frameworks studied had a direct analogue for long-running stateful work that cannot be safely aborted.
