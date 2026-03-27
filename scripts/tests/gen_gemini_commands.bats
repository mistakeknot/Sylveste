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
