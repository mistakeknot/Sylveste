#!/usr/bin/env python3
"""Playtest bridge: connect Shadow Work's debug API to interfere for zero-cost local game playtesting.

Usage:
    python scripts/playtest-bridge.py --campaign climate-cascade
    python scripts/playtest-bridge.py --campaign climate-cascade --model local:qwen3.5-35b-a3b-4bit
    python scripts/playtest-bridge.py --campaign climate-cascade --campaigns-dir ../shadow-work/tools/sw-agent/campaigns

The bridge loops: read game state -> prompt local LLM -> parse action -> execute action.
All inference runs on the local interfere server (localhost:8421), zero cloud API cost.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from pathlib import Path
from typing import Any

import httpx
import yaml

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("playtest-bridge")

# --- Defaults ---
DEFAULT_INTERFERE_URL = "http://localhost:8421"
DEFAULT_GAME_URL = "http://localhost:8790"
DEFAULT_MODEL = "local:qwen3.5-35b-a3b-4bit"
DEFAULT_INTERVAL = 5.0
DEFAULT_MAX_TICKS = 500
DEFAULT_MAX_TOKENS = 256
DEFAULT_CAMPAIGNS_DIR = "../shadow-work/tools/sw-agent/campaigns"

SYSTEM_PROMPT_TEMPLATE = """You are a strategic advisor for Shadow Work, a real-time grand strategy simulation.
The simulation models ~100 fundamental forces across 15 pillars: Climate, Technology,
Diplomacy, Economy, Population, Pandemic, Healthcare, Resource Scarcity, Infrastructure,
Military, Politics, Culture, Institutions, Policy, Public Finance.

You receive game state snapshots including country metrics, emergence signals, and
recent events. Your goal is to advance the campaign's objectives by making strategic
decisions.

{campaign_context}

Respond with ONLY valid JSON (no markdown, no explanation outside the JSON):
{{"action": "<one of: step, pause, speed, recruit, deploy>", "params": {{}}, "reasoning": "brief explanation"}}

Available actions:
- step: advance simulation by N ticks. params: {{"count": 10}}
- pause: pause the simulation. params: {{}}
- speed: set simulation speed. params: {{"value": 1-4}}
- recruit: set agent recruitment state. params: {{"agent_id": "...", "recruitment_state": "recruited"}}
- deploy: create a deployment. params: {{"title": "...", "priority": "high|normal|low"}}
"""


def check_thermal(client: httpx.Client, interfere_url: str) -> bool:
    """Check interfere /health for thermal state. Returns True if safe to proceed."""
    try:
        resp = client.get(f"{interfere_url}/health", timeout=2.0)
        data = resp.json()
        worker = data.get("worker", {})
        # If worker reports thermal info, check it
        thermal = worker.get("thermal_state", 0)
        if thermal >= 2:  # "heavy" pressure
            log.warning("Thermal pressure level %d — pausing inference", thermal)
            return False
        return True
    except Exception:
        return True  # If health check fails, proceed anyway


def fetch_game_state(client: httpx.Client, game_url: str) -> dict[str, Any]:
    """Fetch current game state from sw-agent debug API."""
    state: dict[str, Any] = {}

    try:
        status = client.get(f"{game_url}/diag/status-lite", timeout=5.0)
        state["status"] = status.json()
    except Exception as e:
        log.error("Failed to fetch status: %s", e)
        state["status"] = {}

    try:
        emergence = client.get(f"{game_url}/diag/emergence", timeout=5.0)
        state["emergence"] = emergence.json()
    except Exception as e:
        log.debug("Failed to fetch emergence: %s", e)

    try:
        events = client.get(f"{game_url}/diag/events/feed?limit=10", timeout=5.0)
        state["recent_events"] = events.json()
    except Exception as e:
        log.debug("Failed to fetch events: %s", e)

    return state


def infer_action(
    client: httpx.Client,
    interfere_url: str,
    model: str,
    system_prompt: str,
    game_state: dict[str, Any],
    max_tokens: int = DEFAULT_MAX_TOKENS,
) -> dict[str, Any] | None:
    """Send game state to interfere and parse the response as a JSON action."""
    # Compact the game state to keep prompt tokens manageable
    user_msg = json.dumps(game_state, separators=(",", ":"), default=str)[:4000]

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {
                "role": "user",
                "content": f"Current game state:\n{user_msg}\n\nWhat action should I take?",
            },
        ],
        "max_tokens": max_tokens,
        "temperature": 0.3,
        "stream": True,
    }

    try:
        # Stream the response and collect all tokens
        collected = []
        with client.stream(
            "POST",
            f"{interfere_url}/v1/chat/completions",
            json=payload,
            timeout=120.0,
        ) as resp:
            for line in resp.iter_lines():
                if not line.startswith("data: "):
                    continue
                data_str = line[6:]
                if data_str == "[DONE]":
                    break
                try:
                    chunk = json.loads(data_str)
                    delta = chunk.get("choices", [{}])[0].get("delta", {})
                    content = delta.get("content", "")
                    if content:
                        collected.append(content)
                except json.JSONDecodeError:
                    continue

        full_response = "".join(collected).strip()
        if not full_response:
            log.warning(
                "Empty response from interfere (confidence cascade may have triggered)"
            )
            return None

        # Try to parse as JSON — strip markdown fences if present
        text = full_response
        if text.startswith("```"):
            text = text.split("\n", 1)[1] if "\n" in text else text[3:]
        if text.endswith("```"):
            text = text[:-3]
        text = text.strip()

        return json.loads(text)

    except json.JSONDecodeError:
        log.warning("Failed to parse action JSON: %s", full_response[:200])
        return None
    except Exception as e:
        log.error("Inference request failed: %s", e)
        return None


def execute_action(
    client: httpx.Client,
    game_url: str,
    action: dict[str, Any],
) -> bool:
    """Execute a parsed action against the sw-agent control API."""
    action_type = action.get("action", "step")
    params = action.get("params", {})

    try:
        if action_type == "step":
            count = params.get("count", 10)
            client.post(f"{game_url}/control/step?count={count}", timeout=5.0)
        elif action_type == "pause":
            client.post(f"{game_url}/control/pause", timeout=5.0)
        elif action_type == "speed":
            value = params.get("value", 2)
            client.post(f"{game_url}/control/speed?value={value}", timeout=5.0)
        elif action_type == "recruit":
            client.post(f"{game_url}/control/recruit", json=params, timeout=5.0)
        elif action_type == "deploy":
            client.post(f"{game_url}/control/deployment", json=params, timeout=5.0)
        else:
            log.warning("Unknown action type: %s", action_type)
            return False
        return True
    except Exception as e:
        log.error("Failed to execute %s: %s", action_type, e)
        return False


def load_campaign(campaigns_dir: Path, campaign_name: str) -> dict[str, Any]:
    """Load a campaign YAML file and extract context for the system prompt."""
    campaign_file = campaigns_dir / f"{campaign_name}.yaml"
    if not campaign_file.exists():
        campaign_file = campaigns_dir / f"{campaign_name}.yml"
    if not campaign_file.exists():
        log.warning("Campaign file not found: %s", campaign_file)
        return {}

    with open(campaign_file) as f:
        return yaml.safe_load(f) or {}


def build_campaign_context(campaign: dict[str, Any]) -> str:
    """Extract campaign objective and context for the system prompt."""
    if not campaign:
        return "No specific campaign loaded. Play strategically."

    parts = []
    if "description" in campaign:
        parts.append(f"Campaign: {campaign['description']}")
    if "objective" in campaign:
        parts.append(f"Objective: {campaign['objective']}")
    if "win_condition" in campaign:
        parts.append(f"Win condition: {campaign['win_condition']}")
    if "setup" in campaign:
        parts.append(f"Setup: {json.dumps(campaign['setup'], default=str)}")

    return (
        "\n".join(parts) if parts else "Play strategically to advance the simulation."
    )


def run_assertions(
    client: httpx.Client,
    game_url: str,
    campaign: dict[str, Any],
    tick: int,
) -> tuple[int, int]:
    """Check campaign assertions at the current tick. Returns (passed, total)."""
    assertions = campaign.get("assertions", [])
    if not assertions:
        return 0, 0

    passed = 0
    total = 0

    for assertion in assertions:
        checkpoint_tick = assertion.get("at_tick", assertion.get("tick", 0))
        if checkpoint_tick != tick:
            continue

        total += 1
        # Pause game before reading state (TOCTOU fix)
        try:
            client.post(f"{game_url}/control/pause", timeout=2.0)
        except Exception:
            pass

        try:
            endpoint = assertion.get("endpoint", "/diag/status-lite")
            resp = client.get(f"{game_url}{endpoint}", timeout=5.0)
            state = resp.json()

            field = assertion.get("field", "")
            expected = assertion.get("expected")
            op = assertion.get("op", "eq")

            # Navigate dotted field path
            value = state
            for key in field.split("."):
                if isinstance(value, dict):
                    value = value.get(key)
                else:
                    value = None
                    break

            if op == "eq" and value == expected:
                passed += 1
            elif op == "gt" and value is not None and value > expected:
                passed += 1
            elif op == "lt" and value is not None and value < expected:
                passed += 1
            elif op == "gte" and value is not None and value >= expected:
                passed += 1
            elif op == "exists" and value is not None:
                passed += 1
            else:
                log.warning(
                    "Assertion failed at tick %d: %s %s %s (got %s)",
                    tick,
                    field,
                    op,
                    expected,
                    value,
                )
        except Exception as e:
            log.error("Assertion check failed: %s", e)

        # Resume after assertion
        try:
            client.post(f"{game_url}/control/resume", timeout=2.0)
        except Exception:
            pass

    return passed, total


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Shadow Work playtest bridge for interfere"
    )
    parser.add_argument(
        "--campaign", required=True, help="Campaign name (from campaigns dir)"
    )
    parser.add_argument(
        "--campaigns-dir",
        default=DEFAULT_CAMPAIGNS_DIR,
        help="Path to campaigns directory",
    )
    parser.add_argument("--model", default=DEFAULT_MODEL, help="interfere model ID")
    parser.add_argument("--interfere-url", default=DEFAULT_INTERFERE_URL)
    parser.add_argument("--game-url", default=DEFAULT_GAME_URL)
    parser.add_argument(
        "--interval",
        type=float,
        default=DEFAULT_INTERVAL,
        help="Seconds between actions (after response)",
    )
    parser.add_argument("--max-ticks", type=int, default=DEFAULT_MAX_TICKS)
    parser.add_argument("--max-tokens", type=int, default=DEFAULT_MAX_TOKENS)
    parser.add_argument("--log-file", default=None, help="JSONL log file for decisions")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    campaigns_dir = Path(args.campaigns_dir).resolve()
    campaign = load_campaign(campaigns_dir, args.campaign)
    campaign_context = build_campaign_context(campaign)
    system_prompt = SYSTEM_PROMPT_TEMPLATE.format(campaign_context=campaign_context)

    log_file = open(args.log_file, "a") if args.log_file else None

    client = httpx.Client()

    # Pre-flight checks
    log.info("Checking interfere at %s ...", args.interfere_url)
    try:
        health = client.get(f"{args.interfere_url}/health", timeout=5.0)
        log.info("interfere: %s", health.json().get("status", "unknown"))
    except Exception as e:
        log.error("Cannot reach interfere: %s", e)
        sys.exit(1)

    log.info("Checking Shadow Work at %s ...", args.game_url)
    try:
        status = client.get(f"{args.game_url}/diag/status-lite", timeout=5.0)
        log.info("Shadow Work: tick=%s", status.json().get("tick", "?"))
    except Exception as e:
        log.error("Cannot reach Shadow Work debug API: %s", e)
        sys.exit(1)

    # Campaign setup
    setup = campaign.get("setup", {})
    if setup.get("restart"):
        log.info("Restarting simulation for campaign...")
        client.post(f"{args.game_url}/control/restart", timeout=10.0)
        time.sleep(2)  # Let restart settle

    if setup.get("step_to"):
        target = setup["step_to"]
        log.info("Stepping to tick %d...", target)
        client.post(f"{args.game_url}/control/step?count={target}", timeout=30.0)

    # Main loop
    log.info(
        "Starting playtest bridge: campaign=%s model=%s interval=%.1fs",
        args.campaign,
        args.model,
        args.interval,
    )
    log.info("System prompt length: %d chars", len(system_prompt))

    decisions = 0
    assertions_passed = 0
    assertions_total = 0
    start_time = time.monotonic()

    try:
        while decisions < args.max_ticks:
            # 1. Thermal check before inference
            if not check_thermal(client, args.interfere_url):
                log.info("Thermal throttle — waiting 30s")
                time.sleep(30)
                continue

            # 2. Fetch game state
            game_state = fetch_game_state(client, args.game_url)
            current_tick = game_state.get("status", {}).get("tick", 0)

            # 3. Check if game is done
            if campaign.get("stop_tick") and current_tick >= campaign["stop_tick"]:
                log.info("Reached stop tick %d", campaign["stop_tick"])
                break

            # 4. Infer action (blocks until response completes — response-gated, not wall-clock)
            t0 = time.monotonic()
            action = infer_action(
                client,
                args.interfere_url,
                args.model,
                system_prompt,
                game_state,
                args.max_tokens,
            )
            inference_time = time.monotonic() - t0

            if action is None:
                log.warning(
                    "No action returned (tick=%d, inference_time=%.1fs) — stepping 10",
                    current_tick,
                    inference_time,
                )
                client.post(f"{args.game_url}/control/step?count=10", timeout=5.0)
                decisions += 1
                time.sleep(args.interval)
                continue

            # 5. Execute action
            log.info(
                "tick=%d action=%s reasoning=%s (%.1fs)",
                current_tick,
                action.get("action"),
                action.get("reasoning", "")[:80],
                inference_time,
            )
            execute_action(client, args.game_url, action)
            decisions += 1

            # 6. Log decision
            if log_file:
                entry = {
                    "tick": current_tick,
                    "action": action,
                    "inference_time_s": round(inference_time, 2),
                    "timestamp": time.time(),
                }
                log_file.write(json.dumps(entry) + "\n")
                log_file.flush()

            # 7. Check assertions
            ap, at = run_assertions(client, args.game_url, campaign, current_tick)
            assertions_passed += ap
            assertions_total += at

            # 8. Wait (response-gated — interval starts AFTER action completes)
            time.sleep(args.interval)

    except KeyboardInterrupt:
        log.info("Interrupted by user")
    finally:
        elapsed = time.monotonic() - start_time
        log.info("--- Playtest Summary ---")
        log.info("Campaign: %s", args.campaign)
        log.info("Decisions: %d", decisions)
        log.info("Duration: %.0fs", elapsed)
        if assertions_total > 0:
            pct = assertions_passed / assertions_total * 100
            log.info(
                "Assertions: %d/%d (%.0f%%)", assertions_passed, assertions_total, pct
            )
        else:
            log.info("Assertions: none configured")
        log.info("Model: %s", args.model)
        log.info("Cloud API cost: $0.00")

        if log_file:
            log_file.close()

    # Exit code based on assertion pass rate
    if assertions_total > 0 and assertions_passed / assertions_total < 0.8:
        sys.exit(1)


if __name__ == "__main__":
    main()
