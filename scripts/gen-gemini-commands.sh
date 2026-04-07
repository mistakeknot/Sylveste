#!/usr/bin/env bash
# Generate Gemini CLI custom slash commands from Demarch command markdown.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/.gemini/commands"

usage() {
  cat <<'EOF'
Usage:
  gen-gemini-commands.sh [--output <path>]

Generates Gemini CLI custom command TOML files from Demarch slash-command
markdown sources under os/Clavain/commands and interverse/*/commands.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_DIR="${2:?missing value for --output}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "$OUTPUT_DIR"

markdown_field() {
  local file="$1"
  local field="$2"
  awk -v target="$field" '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm == 1 && $0 == "---" { exit }
    in_fm == 1 && $0 ~ ("^" target ":[[:space:]]*") {
      sub("^" target ":[[:space:]]*", "", $0)
      gsub(/^["'"'"']|["'"'"']$/, "", $0)
      print $0
      exit
    }
  ' "$file"
}

strip_frontmatter() {
  local file="$1"
  awk '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm == 1 && $0 == "---" { in_fm = 0; next }
    in_fm == 0 { print }
  ' "$file"
}

plugin_roots() {
  find "$PROJECT_ROOT/os" "$PROJECT_ROOT/interverse" \
    -mindepth 1 -maxdepth 2 -type d -name commands -print | sort | while read -r commands_dir; do
      dirname "$commands_dir"
    done
}

plugin_name() {
  local plugin_root="$1"
  local plugin_json="$plugin_root/.claude-plugin/plugin.json"
  if [[ -f "$plugin_json" ]] && command -v jq >/dev/null 2>&1; then
    jq -r '.name // empty' "$plugin_json" 2>/dev/null || true
    return
  fi
  basename "$plugin_root" | tr '[:upper:]' '[:lower:]'
}

command_entries() {
  local plugin_root namespace src command_name description
  while IFS= read -r plugin_root; do
    [[ -n "$plugin_root" ]] || continue
    namespace="$(plugin_name "$plugin_root")"
    [[ -n "$namespace" ]] || continue
    for src in "$plugin_root/commands"/*.md; do
      [[ -f "$src" ]] || continue
      command_name="$(markdown_field "$src" "name")"
      description="$(markdown_field "$src" "description")"
      if [[ -z "$command_name" ]]; then
        command_name="$(basename "$src" .md)"
      fi
      printf '%s\t%s\t%s\t%s\n' "$namespace" "$command_name" "$src" "$description"
    done
  done < <(plugin_roots)
}

build_namespace_regex() {
  command_entries | cut -f1 | sort -u | paste -sd'|' -
}

build_command_regex() {
  command_entries | awk -F '\t' -v ns="$1" '$1 == ns { print $2 }' | sort -u | paste -sd'|' -
}

convert_body_for_gemini() {
  local input_file="$1"
  local output_file="$2"
  local namespace="$3"
  local namespace_regex="$4"
  local local_command_regex="$5"

  GEMINI_NAMESPACE="$namespace" \
  GEMINI_NAMESPACE_REGEX="$namespace_regex" \
  GEMINI_LOCAL_COMMAND_REGEX="$local_command_regex" \
  perl -0777 - "$input_file" >"$output_file" <<'PERL'
use strict;
use warnings;

my $namespace = $ENV{GEMINI_NAMESPACE} // '';
my $namespace_regex = $ENV{GEMINI_NAMESPACE_REGEX} // '';
my $local_command_regex = $ENV{GEMINI_LOCAL_COMMAND_REGEX} // '';
local $/;
my $content = <>;

if ($namespace_regex ne '') {
  $content =~ s{(?<![A-Za-z0-9_./:-])/($namespace_regex):([A-Za-z0-9_.-]+)(?=(?:$|[\s\)\]\}\.,;:\!\?\'\"`]))}{"/$1:$2"}ge;
}

if ($namespace ne '' && $local_command_regex ne '') {
  $content =~ s{(?<![A-Za-z0-9_./:-])/($local_command_regex)(?=(?:$|[\s\)\]\}\.,;:\!\?\'\"`]))}{"/$namespace:$1"}ge;
}

$content =~ s/\bAskUserQuestion tool\b/Gemini elicitation adapter/g;
$content =~ s/\bAskUserQuestion\b/Gemini elicitation adapter/g;
$content =~ s/\bSkill tool\b/activate_skill tool/g;
$content =~ s/\bUse the Skill tool\b/Use the activate_skill tool/g;
$content =~ s{\Q~/.claude/\E}{~/.gemini/}g;
$content =~ s{(?<!~)\Q.claude/\E}{.gemini/}g;

print $content;
PERL
}

toml_escape_multiline() {
  perl -0pe 's/"""/\\"""/g'
}

generate_commands() {
  local namespace_regex expected_files entries_file count namespace command_name src description out
  local body_tmp converted_tmp prompt_tmp
  declare -A local_command_regexes=()

  entries_file="$(mktemp)"
  command_entries > "$entries_file"
  namespace_regex="$(cut -f1 "$entries_file" | sort -u | paste -sd'|' -)"
  expected_files="$(mktemp)"
  count=0

  while IFS=$'\t' read -r namespace command_name src description; do
    [[ -n "$namespace" && -n "$command_name" && -n "$src" ]] || continue
    mkdir -p "$OUTPUT_DIR/$namespace"
    out="$OUTPUT_DIR/$namespace/$command_name.toml"
    printf '%s\n' "$out" >> "$expected_files"

    body_tmp="$(mktemp)"
    converted_tmp="$(mktemp)"
    prompt_tmp="$(mktemp)"

    if [[ -z "${local_command_regexes[$namespace]+set}" ]]; then
      local_command_regexes["$namespace"]="$(awk -F '\t' -v ns="$namespace" '$1 == ns { print $2 }' "$entries_file" | sort -u | paste -sd'|' -)"
    fi

    strip_frontmatter "$src" > "$body_tmp"
    convert_body_for_gemini "$body_tmp" "$converted_tmp" "$namespace" "$namespace_regex" "${local_command_regexes[$namespace]}"

    {
      echo "Generated from Demarch slash-command markdown."
      echo
      echo "- Source command: /$namespace:$command_name"
      echo "- Source file: ${src#"$PROJECT_ROOT"/}"
      echo "- When instructions mention Gemini elicitation adapter, ask the user one concise question in chat and wait for the answer."
      echo "- When instructions mention activate_skill tool, use Gemini's activate_skill tool."
      echo
      cat "$converted_tmp"
    } | toml_escape_multiline > "$prompt_tmp"

    {
      echo "# Generated by scripts/gen-gemini-commands.sh. Do not edit by hand."
      if [[ -n "$description" ]]; then
        printf 'description = "%s"\n' "${description//\"/\\\"}"
      else
        printf 'description = "Demarch slash command /%s:%s"\n' "$namespace" "$command_name"
      fi
      echo 'prompt = """'
      cat "$prompt_tmp"
      echo '"""'
    } > "$out"

    rm -f "$body_tmp" "$converted_tmp" "$prompt_tmp"
    count=$((count + 1))
  done < <(command_entries)

  while IFS= read -r existing; do
    [[ -f "$existing" ]] || continue
    if grep -Fq "Generated by scripts/gen-gemini-commands.sh." "$existing" && \
       ! grep -Fxq "$existing" "$expected_files" 2>/dev/null; then
      rm -f "$existing"
    fi
  done < <(find "$OUTPUT_DIR" -type f -name '*.toml' | sort)

  find "$OUTPUT_DIR" -type d -empty -delete
  rm -f "$entries_file"
  rm -f "$expected_files"
  echo "Generated $count Gemini command wrappers in $OUTPUT_DIR"
}

generate_commands
