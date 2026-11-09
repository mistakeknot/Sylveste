#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../gen-gemini-commands.sh"
PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/.."

setup() {
    NPM_GLOBAL=""
    for candidate in /usr/lib/node_modules /usr/local/lib/node_modules; do
        if [[ -d "$candidate/bats-support" ]]; then
            NPM_GLOBAL="$candidate"
            break
        fi
    done
    if [[ -n "$NPM_GLOBAL" ]]; then
        load "$NPM_GLOBAL/bats-support/load"
        load "$NPM_GLOBAL/bats-assert/load"
    fi
}

@test "generates Gemini commands for all Demarch command markdown sources" {
    local outdir expected_count actual_count
    outdir="$(mktemp -d)"

    run bash "$SCRIPT" --output "$outdir"
    [ "$status" -eq 0 ]

    expected_count="$(find "$PROJECT_ROOT/os" "$PROJECT_ROOT/interverse" -mindepth 2 -maxdepth 3 -path '*/commands/*.md' | wc -l | tr -d ' ')"
    actual_count="$(find "$outdir" -type f -name '*.toml' | wc -l | tr -d ' ')"

    [ "$expected_count" = "$actual_count" ]
    [ -f "$outdir/clavain/sprint.toml" ]
    [ -f "$outdir/interflux/flux-drive.toml" ]
}

@test "normalizes Claude-specific instructions for Gemini commands" {
    local outdir route_cmd roadmap_cmd
    outdir="$(mktemp -d)"

    run bash "$SCRIPT" --output "$outdir"
    [ "$status" -eq 0 ]

    route_cmd="$outdir/clavain/route.toml"
    roadmap_cmd="$outdir/interpath/roadmap.toml"

    grep -Fq "Gemini elicitation adapter" "$route_cmd"
    ! grep -Fq "AskUserQuestion" "$route_cmd"
    grep -Fq "activate_skill tool" "$roadmap_cmd"
    ! grep -Fq "Use the Skill tool" "$roadmap_cmd"
}

# Hermetic: builds its own one-plugin tree, so it needs neither os/ nor interverse/.
@test "escapes backslashes, quotes and control characters so the TOML round-trips" {
    python3 -c 'import tomllib' 2>/dev/null || skip "python3 with tomllib (3.11+) is required"

    local tree outdir cmd_dir
    # bats removes BATS_TEST_TMPDIR itself, whether the test passes or fails.
    tree="$BATS_TEST_TMPDIR/tree"
    outdir="$tree/out"
    cmd_dir="$tree/interverse/demo/commands"
    mkdir -p "$tree/scripts" "$tree/os" "$cmd_dir" "$tree/interverse/demo/.claude-plugin"
    cp "$SCRIPT" "$tree/scripts/gen-gemini-commands.sh"
    printf '{"name": "demo"}\n' > "$tree/interverse/demo/.claude-plugin/plugin.json"

    # Body: regex escapes, a literal backslash-n, quote runs, a tab, a CRLF,
    # a bare CR, control characters, and quotes at the very end with no final
    # newline (the generator adds the newline, which the check below expects).
    printf '%s\n' '---' 'name: tricky' 'description: Match \d+ and say "hi" \o/' '---' > "$cmd_dir/tricky.md"
    printf '%s\n' 'grep -E "foo\(bar\)" and sed s/\(a\)/\1/' >> "$cmd_dir/tricky.md"
    printf '%s\n' 'literal \n stays two characters; path C:\Users\x' >> "$cmd_dir/tricky.md"
    printf '%s\n' 'three """ four """" six """""" quotes' >> "$cmd_dir/tricky.md"
    printf 'tab\there, crlf\r\nbare\rcr, bell\a, esc\033, del\177\n' >> "$cmd_dir/tricky.md"
    printf 'ends with quotes ""' >> "$cmd_dir/tricky.md"

    printf '%s\n' '---' 'name: plain' '---' 'Nothing special here.' > "$cmd_dir/plain.md"

    run bash "$tree/scripts/gen-gemini-commands.sh" --output "$outdir"
    [ "$status" -eq 0 ]
    [ -f "$outdir/demo/tricky.toml" ]
    [ -f "$outdir/demo/plain.toml" ]

    run python3 - "$outdir/demo/tricky.toml" "$cmd_dir/tricky.md" "$outdir/demo/plain.toml" <<'PY'
import sys, tomllib

toml_path, src_path, plain_path = sys.argv[1:4]
with open(toml_path, "rb") as fh:
    data = tomllib.load(fh)

raw = open(src_path, "rb").read().decode("utf-8")
body = raw.split("---\n", 2)[2] + "\n"

assert data["description"] == 'Match \\d+ and say "hi" \\o/', repr(data["description"])
# The prompt is a short generated header followed by the body, byte for byte.
assert data["prompt"].endswith(body), repr(data["prompt"][-200:])
assert "Source command: /demo:tricky" in data["prompt"]

with open(plain_path, "rb") as fh:
    plain = tomllib.load(fh)
assert plain["description"] == "Demarch slash command /demo:plain"
assert plain["prompt"].endswith("Nothing special here.\n")
print("ok")
PY
    echo "$output"
    [ "$status" -eq 0 ]
}
