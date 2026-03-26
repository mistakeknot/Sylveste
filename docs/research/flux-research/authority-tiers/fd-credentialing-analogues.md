# Credentialing Analogues: Structural Lessons for Domain-Scoped Agent Authority

> Flux-drive research on how military rank+specialty, medical privileging, and aviation type ratings separate general authority from domain-specific credentials — and what transfers to agent systems.

## 1. Military: Pay Grade vs. Specialty Code

### The Two-Axis System

Every US service member carries two orthogonal identifiers:

- **Pay grade** (E1–E9, O1–O10): hierarchical authority, compensation, time-in-service seniority. A Colonel (O-6) outranks a Captain (O-3) regardless of specialty.
- **Occupation code** (Army MOS, Air Force AFSC, Navy Rate/NEC): domain competence. A 0311 (rifleman) and a 0844 (fire direction controller) are both sergeants but have wholly different operational scopes.

The critical structural insight: **rank grants authority over people; specialty grants authority over domains**. An O-6 in logistics (92A series) commands a logistics brigade. That same O-6 cannot walk onto an infantry battalion's operations floor and direct fire missions — not because they lack rank, but because they lack the domain credential.

### Skill Levels Are Tiered Within Specialty

Air Force AFSCs encode skill level directly in the code structure: a 5-level suffix (Journeyman) vs. 7-level (Craftsman) vs. 9-level (Superintendent). Progression requires both time-in-grade AND demonstrated proficiency — you cannot test into a 7-level without having served as a 5-level for a minimum period. The AFSC system explicitly couples *rank threshold* to *skill tier*: certain specialties have minimum rank requirements (e.g., Infantry Unit Leader 0369 requires Staff Sergeant or above).

### Branch Transfer Requires Requalification

When the Army transfers officers between branches — e.g., Infantry to Logistics — the officer retains their rank but must complete the destination branch's prerequisite training (Captains attend the Logistics C3 course). Rank does not substitute for domain training. The losing branch must release the officer, and caps exist on how many can transfer in each direction.

**Structural principle:** Authority over people (rank) is portable. Authority over a domain (specialty) is not — it requires domain-specific qualification even when general seniority is high.

### Sources

- [Understanding Military Job Codes — Oak and Liberty](https://www.oakandliberty.com/blogs/oak-and-liberty-blogs/understanding-mos-afsc-and-rates-a-simple-guide-to-military-job-codes-for-army-navy-air-force-marine-corps-coast-guard)
- [Air Force Specialty Code — Wikipedia](https://en.wikipedia.org/wiki/Air_Force_Specialty_Code)
- [Army HRC Branch Transfer Program](https://www.army.mil/article/281489/army_hrc_expands_voluntary_branch_transfer_program_seeks_300_yg22_lieutenants_to_rebalance_the_force)
- [Logistics Branch Transfer Requirements](https://alu.army.mil/logpro/Transfer/index.html)

---

## 2. Medical: Hospital Privileging

### Credentialing vs. Privileging — The Separation

Medicine makes the cleanest distinction between general licensure and domain-specific authority:

- **Credentialing** verifies that a physician holds a valid MD/DO license, completed residency, passed boards, and has no sanctions. This is the "rank" equivalent — a baseline threshold for practicing medicine at all.
- **Privileging** is the hospital-specific, procedure-specific grant of authority. A credentialed general surgeon must apply separately for robotic surgery privileges, and the hospital's privileging committee reviews case logs, proctored outcomes, and peer references before granting them.

An MD license alone does not authorize any specific procedure at any specific hospital. Each facility maintains its own privileges matrix.

### Temporary vs. Permanent Privileges

The Joint Commission recognizes two categories of temporary privileges:

1. **Important patient care need**: When no currently privileged practitioner has the required skill, or volume exceeds capacity (locum tenens coverage).
2. **New applicant temporary privileges**: Granted while full credentialing is in progress, with defined time limits and monitoring.

Temporary privileges are time-bounded and require ongoing oversight. They exist because the full credentialing process takes months, and patient care cannot always wait.

### OPPE/FPPE: Continuous Monitoring and Focused Review

- **OPPE** (Ongoing Professional Practice Evaluation): Continuous, metrics-based monitoring of every privileged practitioner — complication rates, readmission rates, peer complaints. Runs in the background permanently.
- **FPPE** (Focused Professional Practice Evaluation): Triggered when OPPE surfaces a concern, or after a sentinel event. The practitioner operates under direct proctoring with defined metrics that must be met within a time window.

The escalation ladder is graduated:

1. **OPPE flags anomaly** → department chair counseling
2. **FPPE initiated** → proctored practice, education plan, mentoring
3. **FPPE failure** → privilege restriction or termination
4. **Summary suspension** → immediate removal of all privileges, reserved for imminent patient safety threats

### Summary Suspension: The Emergency Brake

Summary suspension bypasses the graduated process entirely. It requires documented immediate threat to patient safety, is reportable to the National Practitioner Data Bank (a permanent record), and triggers due-process hearing rights. It is the nuclear option — used rarely, with high institutional cost.

**Structural principle:** Domain authority (privileges) is granted per-procedure, per-facility, with continuous monitoring. General licensure (credentials) is necessary but not sufficient. Escalation follows a defined ladder from background monitoring to focused review to restriction to emergency revocation.

### Sources

- [Joint Commission — Temporary Privileges FAQ](https://www.jointcommission.org/standards/standard-faqs/hospital-and-hospital-clinics/medical-staff-ms/000002257/)
- [StatPearls — Credentialing](https://www.ncbi.nlm.nih.gov/books/NBK519504/)
- [symplr — FPPE and OPPE Guide](https://www.symplr.com/blog/complete-guide-to-oppe-fppe-review-process-requirements)
- [Courtemanche — FPPE/OPPE Lessons Learned](https://www.courtemanche-assocs.com/blogs/fppe-oppe-lessons-learned)

---

## 3. Aviation: Type Ratings and Currency

### The Layered Certificate Stack

FAA pilot certification is explicitly hierarchical and domain-scoped:

| Layer | What it grants | Analogy |
|-------|---------------|---------|
| **Student/Private/Commercial/ATP** | General privilege tier (passenger-carrying, compensation, airline ops) | Pay grade |
| **Category & Class** (airplane single-engine land, rotorcraft helicopter) | Broad vehicle family | Branch of service |
| **Type Rating** (B737, A320, CL-30) | Authority to act as PIC of a specific aircraft type | MOS/procedure privilege |

An ATP certificate holder with 10,000 hours in Boeing 737s cannot legally act as PIC of an Airbus A320 without obtaining a separate A320 type rating — which requires aircraft-specific ground school, simulator training, and a practical exam (checkride). Type ratings are required for any aircraft over 12,500 lbs MTOW or any turbojet.

### Currency: Authority Decays Without Use

Holding a certificate and type rating is not enough. Currency requirements impose recency gates:

- **Passenger-carrying currency**: 3 takeoffs and landings in the preceding 90 days *in the same type/class of aircraft*. Night currency adds 3 full-stop landings at night.
- **Instrument currency**: 6 instrument approaches, holding procedures, and intercepting/tracking courses within the preceding 6 calendar months. Lapse triggers a mandatory instrument proficiency check (IPC) with an instructor.
- **Flight review**: Every 24 calendar months, regardless of total experience.
- **Part 121/135 operations** (airlines/charters): Recurrent training and proficiency checks every 6–12 months, administered by company check airmen.

Currency is domain-specific: being current in a 737 does not make you current in a 747, even if you hold both type ratings.

### The 709 Ride: Reexamination on Suspicion

Under 14 CFR 61.58, the FAA can require any certificate holder to demonstrate competency at any time via a "709 ride" (named after the old section number). This is the aviation equivalent of FPPE — a targeted reexamination triggered by evidence of competency concerns. The graduated enforcement ladder:

1. **No action** — investigation finds no violation
2. **Compliance action** — counseling and education (most common)
3. **709 reexamination** — demonstrate competency to an examiner; pass restores full privileges, fail initiates revocation proceedings
4. **Certificate suspension** — fixed duration (punitive) or indefinite (pending demonstration of competence)
5. **Certificate revocation** — permanent loss; must start from zero to recertify

**Structural principle:** Authority requires (a) a general privilege tier, (b) a domain-specific rating obtained through evaluation, and (c) continuous recency-of-use to remain valid. Authority that isn't exercised degrades to an inactive state requiring requalification.

### Sources

- [American Flyers — Type Rating Explained](https://americanflyers.com/what-is-a-type-rating-and-when-is-it-required/)
- [LegalClarity — FAA Currency Requirements](https://legalclarity.org/faa-currency-requirements-and-regulations-for-pilots/)
- [AOPA — Demystifying 709 Reexaminations](https://pilot-protection-services.aopa.org/news/2022/december/01/demystifying-709-reexaminations)
- [FAA — Legal Enforcement Actions](https://www.faa.gov/about/office_org/headquarters_offices/agc/practice_areas/enforcement/enforcement_actions)

---

## 4. Cross-Domain Structural Patterns

Five patterns recur across all three domains:

### Pattern 1: Separation of General Rank from Domain Credential

| Domain | General authority | Domain credential |
|--------|-----------------|-------------------|
| Military | Pay grade (E/O scale) | MOS/AFSC specialty code |
| Medicine | MD license + board certification | Hospital-specific procedure privileges |
| Aviation | Pilot certificate level (PPL/CPL/ATP) | Type rating per aircraft |

In every case, the general credential is *necessary but not sufficient* for domain action. High general rank without the domain credential confers zero operational authority in that domain.

### Pattern 2: Currency/Recency Requirements

All three systems treat competence as **perishable**:

- Military: Annual qualification on weapon systems, periodic MOS-specific recertification
- Medicine: OPPE runs continuously; privileges are reappraised every 2 years at reappointment
- Aviation: 90-day passenger currency, 6-month instrument currency, 24-month flight review, annual line checks

The universal insight: **a credential at time T does not guarantee competence at time T+delta.** Systems that lack recency requirements suffer credential inflation.

### Pattern 3: Peer-Review Gates (Not Just Self-Assessment)

Domain credentials in all three systems require evaluation by domain peers:

- Military: Promotion boards include senior officers from the same branch; MOS qualification is assessed by MOS-qualified evaluators
- Medicine: Privileging committees include department-specific physicians who review case logs and outcomes
- Aviation: Type rating checkrides are administered by designated pilot examiners (DPEs) who hold the same type rating; 121/135 proficiency checks are given by company check airmen

No system allows pure self-certification for domain authority.

### Pattern 4: Graduated Escalation with Emergency Override

All three systems maintain a remediation ladder that goes from monitoring → focused review → restriction → revocation, PLUS an emergency bypass:

| Stage | Military | Medical | Aviation |
|-------|----------|---------|----------|
| Background monitoring | OER/NCOER evaluations | OPPE metrics | Recurrent training records |
| Focused review | Article 15 / LOC | FPPE proctoring | 709 reexamination |
| Restriction | Relief from duty | Privilege limitation | Certificate suspension |
| Removal | Court martial / separation | Summary suspension + revocation | Certificate revocation |
| Emergency bypass | Commander's authority to relieve | Summary suspension (immediate) | Emergency revocation order |

The emergency bypass exists because graduated processes take time, and some failures are immediately dangerous.

### Pattern 5: Portability Boundaries

- Military rank transfers across duty stations; MOS transfers with requalification
- MD license is state-scoped; hospital privileges are facility-scoped and non-portable
- Pilot certificates are nationally valid; airline-specific operating authority (Part 121 authorization) is employer-scoped

Domain credentials are always *less portable* than general credentials. Moving to a new context requires some degree of revalidation.

---

## 5. Failure Modes

### Credential Inflation

When the barrier to obtaining a domain credential drops below the level needed for competent performance. In medicine, this manifests as "see one, do one, teach one" culture granting privileges without adequate case volume. In aviation, type rating mills that optimize for checkride pass rates over genuine aircraft mastery. In military, automatic MOS upgrades tied purely to time-in-grade without skill verification.

**Agent equivalent:** Granting a tool-use or domain credential after a single successful invocation rather than sustained demonstrated competence.

### Scope Creep

When a credential holder gradually expands their operational scope beyond what was explicitly granted. A hospitalist who starts performing procedures not on their privilege list. A pilot who flies beyond their type rating limitations in non-standard configurations. A military specialist who takes on tasks from an adjacent MOS without requalification.

**Agent equivalent:** An agent authorized for read-only database access that gradually begins issuing write queries because nothing enforces the boundary at runtime.

### Rubber-Stamp Review

When peer-review gates become formalities rather than genuine evaluations. Small hospital privileging committees that approve every application. Military promotion boards with predetermined outcomes. Airlines where recurrent training is a check-the-box exercise.

**Countermeasures observed:**
- External audit requirements (Joint Commission surveys, FAA ramp checks, IG inspections)
- Mandatory outcome metrics that are harder to fake than process compliance
- Separation between the granting body and the auditing body

### Audit Lag

The gap between when competence degrades and when the system detects it. OPPE cycles that run quarterly miss rapid deterioration. 24-month flight reviews are too infrequent for pilots who fly rarely. Military annual evaluations miss skill atrophy between assessment periods.

**Agent equivalent:** A credential review cycle that checks agent performance monthly while the agent processes thousands of requests daily — failures accumulate before review catches them.

---

## 6. Translation to Agent Authority

### What Is the Agent Equivalent of Each Mechanism?

| Human institution mechanism | Agent system equivalent |
|----------------------------|------------------------|
| **Type rating exam** | Domain-specific evaluation suite — not a single test but a battery of tasks that probe edge cases, error handling, and judgment within a specific tool/API/domain. Must be passed before the agent gains access to that domain. Scored by an evaluator agent or deterministic harness, not self-assessed. |
| **Privileges committee** | A policy gate that combines: (a) evaluation results, (b) historical performance metrics in the domain, (c) risk profile of the domain (destructive operations = higher bar). Could be a configuration-as-code review, an orchestrator decision, or a human-in-the-loop approval for high-risk domains. |
| **Currency requirements** | Performance metric decay — an agent's domain credential includes a recency window. If the agent hasn't operated in that domain within N time units, or if its rolling success rate drops below threshold, the credential downgrades to "needs requalification." Requalification is a subset of the original evaluation, not the full battery. |
| **OPPE (background monitoring)** | Continuous telemetry on every domain invocation — error rates, latency, user correction frequency, output quality scores. Runs permanently, feeds into credential status. |
| **FPPE (focused review)** | Triggered review mode — when OPPE metrics cross a threshold, the agent operates under heightened scrutiny: outputs are double-checked by a reviewer agent or human, sample rate for quality evaluation increases, and the agent must demonstrate recovery within a bounded period or lose the credential. |
| **Summary suspension** | Immediate credential revocation via circuit breaker — when a domain invocation causes a critical failure (data loss, security breach, user harm), the agent's access to that domain is severed in real-time, before the next request. No graduated process. |
| **709 ride** | On-demand reexamination — an orchestrator or human can trigger a targeted competency check at any time, not just on a schedule. The agent must pass to retain the credential. |
| **Branch transfer requalification** | When an agent trained/evaluated on Domain A is asked to operate in Domain B, it cannot carry over Domain A credentials. It must pass Domain B's evaluation suite independently, even if the domains seem adjacent. |

### Design Implications for Demarch

1. **Two-axis authority model**: Agent authority should be factored into (a) a general trust tier (analogous to pay grade — how much autonomy the agent gets in any domain) and (b) domain-specific credentials (analogous to type ratings — which specific tools, APIs, or action classes the agent is authorized for).

2. **Credentials are non-transitive**: Authorization for `git commit` does not imply authorization for `git push --force`. Each destructive or domain-specific action class requires its own credential, obtained through domain-specific evaluation.

3. **Currency windows on every credential**: A credential that hasn't been exercised and validated within its recency window degrades to "inactive." Inactive credentials require requalification (a lighter version of initial evaluation), not just a flag flip.

4. **Continuous background telemetry (OPPE-equivalent)**: Every domain invocation feeds performance metrics. These metrics are the primary input to credential maintenance — not periodic batch reviews.

5. **Graduated response with emergency brake**: The default path for degraded performance is focused review → restriction → revocation. But the system must also support immediate suspension (circuit breaker) for critical failures, with the trigger being outcome severity rather than process stage.

6. **Peer evaluation, not self-assessment**: Domain credentials should be granted by evaluation harnesses or reviewer agents that are independent of the agent being evaluated. Self-reported success metrics are the agent equivalent of rubber-stamp review.

7. **Temporary credentials for urgent needs**: Like medical temporary privileges, an agent may be granted time-limited, closely-monitored access to a new domain when no credentialed agent is available — but with mandatory expiration and heightened oversight.

---

## Summary Table

| Structural Property | Military | Medical | Aviation | Agent Design Implication |
|---------------------|----------|---------|----------|--------------------------|
| General vs. domain authority | Pay grade vs. MOS | License vs. privileges | Certificate vs. type rating | Trust tier vs. domain credential |
| Domain credential granularity | Per-MOS (hundreds) | Per-procedure | Per-aircraft type | Per-tool/API/action-class |
| Credential portability | MOS transfers with retraining | Privileges are per-facility | Type ratings are national, airline auth is per-employer | Credentials may be per-deployment-context |
| Recency requirement | Annual requalification | 2-year reappointment + continuous OPPE | 90-day / 6-month / 24-month cycles | Configurable decay window per domain |
| Peer review gate | Branch-qualified evaluators | Department-specific privilege committee | DPE / check airman | Independent evaluator agent or harness |
| Emergency revocation | Commander relief | Summary suspension | Emergency certificate action | Circuit breaker / immediate credential revocation |
| Failure detection | OER/NCOER cycle | OPPE telemetry | Recurrent checks + incident reports | Continuous invocation telemetry |

<!-- flux-research:complete -->
