# Hermes Patterns: What's Portable to Intercom

**Analysis Date:** 2026-03-02
**Goal:** Extract reusable defensive patterns from Hermes without wholesale adoption.

---

## Pattern 1: Always-Log-Local (Crash-Safe Audit)

### Hermes Implementation
```python
# scheduler.py:306–326
def run_job(job):
    output = job.get("full_output_doc", "")
    final_response = job.get("final_response", "")

    # STEP 1: Persist output to disk (durable before network send)
    output_file = save_job_output(job["id"], output)

    # STEP 2: Deliver to remote (may fail)
    try:
        _deliver_result(job, final_response)
    except Exception as de:
        logger.error("Delivery failed: %s", de)

    # STEP 3: Mark complete (one atomic call)
    mark_job_run(job["id"], success=True, error=None)
```

**Why it works:**
- Job output is persisted BEFORE Telegram send
- If network fails, audit trail is intact
- If Telegram succeeds, mark_job_run() confirms in DB
- On crash between steps, next tick sees incomplete marker

### How Intercom Should Adapt
```rust
// scheduler_wiring.rs

async fn run_scheduled_task(...) {
    let start = Instant::now();

    // STEP 1: Run container, capture output
    let output = run_container_agent(...).await;

    // STEP 2: Log to Postgres (durable first)
    pool.log_task_run(task.id, output.clone()).await?;

    // STEP 3: Send to Telegram (may fail)
    if let Err(e) = telegram.send_message(..., output).await {
        error!("Failed to send to Telegram: {}", e);
        // But log is already persisted, so we don't lose output
    }

    // STEP 4: Update next_run (atomic with log)
    let next = calculate_next_run(...);
    pool.update_task_after_run(task.id, next).await?;

    // ^-- P1-002 from SYNTHESIS: wrap steps 2 & 4 in one transaction
}
```

**Implementation diff:**
- Split container run from Telegram delivery
- Always persist output before sending
- Update next_run as separate (but transactional) step
- Log delivery failures but continue

**Benefit:** If daemon crashes mid-Telegram-send, the log + next_run are already updated. No re-execution.

---

## Pattern 2: File-Lock Dispatch Exclusion (TOCTOU Protection)

### Hermes Implementation
```python
# scheduler.py:285–291
def tick(verbose=True):
    _LOCK_DIR.mkdir(parents=True, exist_ok=True)

    try:
        lock_fd = open(_LOCK_FILE, "w")
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)  # Exclusive, non-blocking
    except (OSError, IOError):
        logger.debug("Tick skipped — another instance holds the lock")
        return 0  # Exit early if lock is held

    try:
        due_jobs = get_due_jobs()
        for job in due_jobs:
            run_job(job)
            mark_job_run(job["id"], success=True)
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        lock_fd.close()
```

**Why it works:**
- Filesystem provides atomic mutual exclusion
- Two concurrent ticks can't both run (one gets lock, other skips)
- Prevents double-execution under rolling updates or systemd timer race

### How Intercom Should Adapt (Better: SQL)
```rust
// scheduler.rs:150–200

async fn run_scheduler_loop(...) {
    loop {
        tokio::select! {
            _ = tokio::time::sleep(config.poll_interval) => {}
            _ = shutdown.changed() => { return; }
        }

        // Atomically claim due tasks (P1-001)
        let due_tasks = pool.query(
            "SELECT id, group_folder, chat_jid, prompt, ...
             FROM scheduled_tasks
             WHERE next_run <= now() AND status = 'active'
             FOR UPDATE SKIP LOCKED  -- ← Only this instance sees these rows
             LIMIT ?",
            &[&batch_size]
        ).await?;

        for task in due_tasks {
            // At this point, no other daemon can claim this task
            task_callback(task);
        }
    }
}
```

**Why SQL is better than file-lock:**
- Works across machines (Kubernetes, distributed)
- Database semantics are clearer (FOR UPDATE is standardized)
- No filesystem dependency (works in cloud)
- Integrates with transaction model (SKIP LOCKED + transaction = atomicity)

**Hermes's file-lock is:**
- ✓ Simple to understand
- ✓ Cross-process mutual exclusion
- ✗ Filesystem-only (doesn't scale to multi-machine)
- ✗ Not observable (can't query lock state)

**Intercom's SQL approach:**
- ✓ Distributed (works in Kubernetes)
- ✓ Observable (query scheduled_tasks status)
- ✓ Integrated with other data (same transaction)
- ✗ Slightly more complex (SQL syntax)

---

## Pattern 3: Redaction Library (Credential Protection)

### Hermes Implementation
```python
# agent/redact.py:1–116

PATTERNS = {
    "AWS_KEY": r"AKIA[0-9A-Z]{16}",
    "JWT": r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+",
    "PRIVATE_KEY": r"-----BEGIN [A-Z ]+ PRIVATE KEY-----",
    "DB_URL": r"(postgres|mysql|mongodb):\/\/[^\s@]+@[^\s\/]+\/[^\s]+",
    "API_KEY": r"(sk-|pk-|api-key)[A-Za-z0-9_-]{32,}",
}

class RedactingFormatter(logging.Formatter):
    """Applied to all logging handlers — catches credentials in logs"""
    def format(self, record):
        message = super().format(record)
        return redact_sensitive_text(message)

def redact_sensitive_text(text):
    """Replace sensitive patterns with placeholders"""
    for pattern_name, pattern in PATTERNS.items():
        text = re.sub(pattern, f"[REDACTED_{pattern_name}]", text)
    return text

# Applied at three layers:
# 1. Logging: RedactingFormatter on all handlers
# 2. File I/O: _secure_write() reads file, redacts, writes back
# 3. Session mirroring: mirror_to_session() redacts before storing
```

### How Intercom Should Adapt
**Create `core/redact/redact.go`:**

```go
package redact

import (
    "log/slog"
    "regexp"
    "strings"
)

var patterns = map[string]*regexp.Regexp{
    "AWS_KEY":     regexp.MustCompile(`AKIA[0-9A-Z]{16}`),
    "JWT":         regexp.MustCompile(`eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+`),
    "PRIVATE_KEY": regexp.MustCompile(`-----BEGIN [A-Z ]+ PRIVATE KEY-----`),
    "DB_URL":      regexp.MustCompile(`(postgres|mysql|mongodb)://[^\s@]+@[^\s/]+/[^\s]+`),
    "API_KEY":     regexp.MustCompile(`(sk-|pk-|api-key)[A-Za-z0-9_-]{32,}`),
    "JWT_SECRET":  regexp.MustCompile(`(secret|password)[\"']?\s*=\s*[\"']?[A-Za-z0-9_-]{32,}`),
}

// Redact returns a redacted copy of text
func Redact(text string) string {
    for name, re := range patterns {
        text = re.ReplaceAllString(text, "[REDACTED_"+name+"]")
    }
    return text
}

// NewRedactingHandler wraps slog.Handler with redaction
func NewRedactingHandler(h slog.Handler) slog.Handler {
    return &redactingHandler{next: h}
}

type redactingHandler struct {
    next slog.Handler
}

func (h *redactingHandler) Handle(ctx context.Context, r slog.Record) error {
    // Redact the message before logging
    r.Message = Redact(r.Message)
    // Also redact all attributes
    r.Attrs(func(attr slog.Attr) bool {
        if s, ok := attr.Value.Any().(string); ok {
            attr = slog.Attr{Key: attr.Key, Value: slog.StringValue(Redact(s))}
        }
        return true
    })
    return h.next.Handle(ctx, r)
}
```

**Apply everywhere:**

```rust
// In persistence.rs (session storage)
pub async fn store_session(&self, session: &SessionData) -> Result<()> {
    let json = serde_json::to_string(session)?;
    let redacted = redact::Redact(&json);  // ← Apply before write
    self.db.execute(
        "INSERT INTO sessions (group_folder, session_json) VALUES (?, ?)",
        [&group_folder, &redacted],
    )?;
    Ok(())
}

// In scheduler_wiring.rs (task output)
let output = run_container_agent(...).await?;
let redacted_output = redact::Redact(&output);  // ← Apply before log
pool.log_task_run(task.id, &redacted_output).await?;
```

**Patterns to add (beyond Hermes):**
- OpenAI API keys: `sk-[A-Za-z0-9]{20,}`
- Anthropic API keys: same as OpenAI
- OAuth tokens: `oauth_[A-Za-z0-9_-]{32,}`
- Intercom secret token (if used): project-specific patterns

**Why this is critical:**
- P0-001 from SYNTHESIS: session JSON written without redaction
- Audit logs contain credentials after tool execution
- Postgres logs can be queried by ops, exposing secrets

---

## Pattern 4: Pairing/User Authorization (OTP + Rate Limit)

### Hermes Implementation
```python
# gateway/pairing.py:45–87

class PairingStore:
    """Manages user authorization via OTP"""

    def __init__(self):
        self.pairs = {}  # user_id → {"otp": "123456", "created_at": time, "attempts": 0}

    def request_pairing(self, user_id):
        """Generate OTP and send via Telegram"""
        otp = str(random.randint(100000, 999999))
        self.pairs[user_id] = {
            "otp": otp,
            "created_at": time.time(),
            "attempts": 0,
            "locked_until": None,
        }
        # Send OTP via Telegram
        send_message(user_id, f"Your pairing code: {otp} (expires in 10 min)")

    def verify_pairing(self, user_id, otp_input):
        """Verify OTP with rate limiting and lockout"""
        entry = self.pairs.get(user_id)
        if not entry:
            return False, "No pairing request"

        # Check lockout
        if entry["locked_until"] and time.time() < entry["locked_until"]:
            return False, "Too many attempts, locked for 5 min"

        # Check expiry
        if time.time() - entry["created_at"] > 600:  # 10 min
            return False, "OTP expired"

        # Check attempts
        if entry["attempts"] >= 3:
            entry["locked_until"] = time.time() + 300  # 5 min lockout
            return False, "Too many attempts"

        # Verify
        if otp_input != entry["otp"]:
            entry["attempts"] += 1
            return False, f"Invalid OTP ({3 - entry['attempts']} attempts left)"

        # Success
        del self.pairs[user_id]
        return True, "Paired"
```

### How Intercom Should Adapt
**Create `core/pairing/pairing.go`:**

```rust
pub struct PairingStore {
    store: Arc<Mutex<HashMap<String, PairingEntry>>>,
}

struct PairingEntry {
    otp: String,
    created_at: Instant,
    attempts: u32,
    locked_until: Option<Instant>,
}

impl PairingStore {
    pub fn request_pairing(&self, user_id: &str) -> String {
        let otp = format!("{:06}", rand::random::<u32>() % 1_000_000);
        let mut store = self.store.lock().unwrap();
        store.insert(user_id.to_string(), PairingEntry {
            otp: otp.clone(),
            created_at: Instant::now(),
            attempts: 0,
            locked_until: None,
        });
        otp
    }

    pub fn verify_pairing(&self, user_id: &str, otp_input: &str) -> Result<bool, String> {
        let mut store = self.store.lock().unwrap();
        let entry = store.get_mut(user_id)
            .ok_or("No pairing request")?;

        if let Some(locked) = entry.locked_until {
            if Instant::now() < locked {
                return Err("Too many attempts, locked".to_string());
            }
            entry.locked_until = None;
        }

        if entry.created_at.elapsed() > Duration::from_secs(600) {
            store.remove(user_id);
            return Err("OTP expired".to_string());
        }

        if entry.attempts >= 3 {
            entry.locked_until = Some(Instant::now() + Duration::from_secs(300));
            return Err("Too many attempts".to_string());
        }

        if otp_input != entry.otp {
            entry.attempts += 1;
            return Ok(false);
        }

        store.remove(user_id);
        Ok(true)
    }
}
```

**Replace Intercom's static allowlist:**
```rust
// Before: hard-coded in config
if !config.telegram.allowed_users.contains(&user_id) {
    return Err("Not authorized");
}

// After: use PairingStore
if !pairing_store.is_paired(user_id)? {
    pairing_store.request_pairing(user_id)?;
    return Err("Pairing code sent via Telegram");
}
```

**Why this is valuable:**
- Replaces static allowlist (not scalable)
- Supports dynamic user onboarding
- Rate-limiting prevents brute-force attacks
- Lockout prevents DoS (if attacker knows a user_id)

---

## Pattern 5: Delivery Target DSL (Output Routing)

### Hermes Implementation
```python
# delivery.py:64–90

deliver = job.get("deliver", "local")

if deliver == "local":
    # Don't send to any platform, just save to disk
    return
elif deliver == "origin":
    # Send to the chat where the user triggered the job
    platform_name = origin["platform"]
    chat_id = origin["chat_id"]
elif ":" in deliver:
    # Send to specific platform:chat_id
    platform_name, chat_id = deliver.split(":", 1)
else:
    # Bare platform name — resolve to home channel
    platform_name = deliver
    chat_id = os.getenv(f"{platform_name.upper()}_HOME_CHANNEL")

# Now send to the resolved platform
_send_to_platform(platform_name, chat_id, content)
```

### How Intercom Should Adapt
```rust
// In types.rs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum DeliveryTarget {
    /// Don't send to any platform
    Local,
    /// Send to the chat where the user triggered it
    Origin { platform: String, chat_id: String },
    /// Send to a specific platform + chat_id
    Platform { platform: String, chat_id: String },
    /// Send to the configured home channel for a platform
    HomeChannel { platform: String },
}

impl DeliveryTarget {
    pub fn from_string(s: &str, origin: Option<(&str, &str)>) -> Result<Self> {
        match s {
            "local" => Ok(Self::Local),
            "origin" => {
                let (platform, chat_id) = origin.ok_or("No origin available")?;
                Ok(Self::Origin {
                    platform: platform.to_string(),
                    chat_id: chat_id.to_string(),
                })
            }
            s if s.contains(':') => {
                let (platform, chat_id) = s.split_once(':').ok_or("Invalid format")?;
                Ok(Self::Platform {
                    platform: platform.to_string(),
                    chat_id: chat_id.to_string(),
                })
            }
            platform => {
                Ok(Self::HomeChannel {
                    platform: platform.to_string(),
                })
            }
        }
    }
}

// In scheduler_wiring.rs
let delivery = DeliveryTarget::from_string(&task.deliver, Some(("telegram", &task.chat_jid)))?;
match delivery {
    DeliveryTarget::Local => {}  // Don't send
    DeliveryTarget::Origin { platform, chat_id } => telegram.send(&platform, &chat_id, &output).await?,
    DeliveryTarget::Platform { platform, chat_id } => telegram.send(&platform, &chat_id, &output).await?,
    DeliveryTarget::HomeChannel { platform } => {
        let chat_id = config.home_channels.get(&platform).ok_or("No home channel")?;
        telegram.send(&platform, chat_id, &output).await?
    }
}
```

**Why this is clean:**
- Separates task output from routing logic
- DSL is human-readable (can be user-facing)
- Extensible to new platforms without code changes
- Optional feature (low priority, but portable)

---

## Patterns NOT to Port

### ❌ File-Based Job Store
Hermes stores jobs in JSON files:
```python
~/.hermes/cron/jobs.json
[
  {
    "id": "job_123",
    "prompt": "...",
    "schedule": "0 10 * * *",  # Daily at 10am
    "deliver": "origin"
  }
]
```

**Why Intercom is better with Postgres:**
- Distributed queries (can't query filesystem)
- Atomic updates (transactions)
- ACID guarantees
- Scalable to 1000s of tasks

### ❌ Modal Terminal Backends
Hermes supports:
- Local bash execution
- Docker containers
- SSH remote execution

**Why Intercom's containerized approach is better:**
- Consistent execution environment
- Isolation by default
- No SSH key management
- Easier to scale (k8s-native)

### ❌ In-Process Async Gateway
Hermes runs cron + gateway in same process:
```python
# Same asyncio loop handles:
# - Cron tick (get_due_jobs)
# - Telegram polling
# - Message routing
```

**Why Intercom's async decoupling is better:**
- IPC polling doesn't block scheduler
- Scheduler doesn't block message processing
- Can scale independently (daemon + Node on separate machines)

---

## Portable Patterns Summary

| Pattern | Hermes File | Intercom Target | Priority | Effort |
|---------|-------------|-----------------|----------|--------|
| Always-log-local | `scheduler.py:306–326` | `scheduler_wiring.rs` | P1 (implemented via transactions) | Done |
| Atomic dispatch | `scheduler.py:285–291` | SQL `FOR UPDATE SKIP LOCKED` | P1 | 1d |
| Redaction library | `agent/redact.py` | `core/redact/redact.go` | P0 | 3d |
| Pairing/OTP | `gateway/pairing.py` | `core/pairing/pairing.rs` | P1 (medium-term) | 3d |
| Delivery target DSL | `delivery.py` | `types.rs::DeliveryTarget` | P2 | 2d |

**Total effort for all patterns:** ~9 days (most are independent).

---

## Hermes Anti-Patterns to AVOID

| Anti-Pattern | Hermes | Why Bad | Intercom Avoids |
|--------------|--------|--------|-----------------|
| Fire-and-forget delivery | `delivery.py:130–140` | No retry, no ack | LISTEN/NOTIFY with retry |
| Single-threaded job execution | `ThreadPoolExecutor(max_workers=1)` | No fairness, no parallelism | Per-group queue with concurrency cap |
| Session state in Python dicts | `gateway/session.py` | Lost on restart | Postgres-persisted sessions |
| Hardcoded allowed_users list | `config.yaml` | Not scalable | PairingStore with OTP |
| No timeout enforcement | `agent/run_agent.py` | Can hang forever | `tokio::time::timeout` |

