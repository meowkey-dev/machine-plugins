#!/usr/bin/env bash
# _config.sh — shared config loader for assets plugin scripts
#
# Source this file (don't execute it). After sourcing, the following are available:
#   GLOBAL_CONFIG, LOCAL_CONFIG  — resolved config file paths
#   _yaml_field file section field       — extract a two-level YAML value
#   _yaml_nested_field file s1 s2 field  — extract a three-level YAML value
#   _yaml_list file section field        — extract an inline YAML list as lines
#   _config section field [ENV_VAR] [default]         — layered two-level config
#   _config_nested s1 s2 field [ENV_VAR] [default]    — layered three-level config
#   _config_list s1 s2 field                          — layered three-level list config

# ── config file resolution ──────────────────────────────────────────────────

GLOBAL_CONFIG="${HOME}/.claude/plugins/assets/config.yaml"
LOCAL_CONFIG=""

# Walk up from cwd looking for a repo-local config. The canonical path is
# .claude/assets/config.yaml (issue #127 — aligns with the .claude/ convention).
# The legacy .assets/config.yaml is honored as a back-compat fallback with a
# deprecation warning; drop the fallback in v0.4.0 (or when a follow-up issue says).
_walk_dir="${ASSETS_CONFIG_CWD:-$PWD}"
while [[ "$_walk_dir" != "/" ]]; do
    if [[ -f "${_walk_dir}/.claude/assets/config.yaml" ]]; then
        LOCAL_CONFIG="${_walk_dir}/.claude/assets/config.yaml"
        break
    elif [[ -f "${_walk_dir}/.assets/config.yaml" ]]; then
        LOCAL_CONFIG="${_walk_dir}/.assets/config.yaml"
        echo "assets: using legacy ${LOCAL_CONFIG}; move to ${_walk_dir}/.claude/assets/config.yaml at your leisure (legacy path support drops in v0.4.0)" >&2
        break
    fi
    _walk_dir="$(dirname "$_walk_dir")"
done
unset _walk_dir

# ── YAML field extractors ───────────────────────────────────────────────────

# Two-level: section.field (e.g. tmux.socket)
_yaml_field() {
    local file="$1" section="$2" field="$3"
    [[ -f "$file" ]] || return 0
    awk -v sec="${section}:" -v fld="${field}:" '
        $0 ~ "^" sec "[[:space:]]*(#.*)?$" { in_sec=1; next }
        /^[^[:space:]]/ { in_sec=0 }
        in_sec {
            line = $0
            gsub(/^[[:space:]]+/, "", line)
            if (index(line, fld) == 1) {
                val = substr(line, length(fld)+1)
                gsub(/^[[:space:]]+/, "", val)
                gsub(/[[:space:]]*#.*$/, "", val)
                gsub(/^"/, "", val); gsub(/"$/, "", val)
                gsub(/^'"'"'/, "", val); gsub(/'"'"'$/, "", val)
                print val
                exit
            }
        }
    ' "$file" 2>/dev/null | head -1
}

# Three-level: section.subsection.field (e.g. tmux.remote.host)
_yaml_nested_field() {
    local file="$1" section="$2" subsection="$3" field="$4"
    [[ -f "$file" ]] || return 0
    awk -v sec="${section}:" -v subsec="${subsection}:" -v fld="${field}:" '
        $0 ~ "^" sec "[[:space:]]*(#.*)?$" { in_sec=1; next }
        /^[^[:space:]]/ { in_sec=0; in_subsec=0 }
        in_sec {
            line = $0
            gsub(/^[[:space:]]+/, "", line)
            if (!in_subsec && index(line, subsec) == 1) { in_subsec=1; next }
            if (in_subsec && $0 ~ /^  [^[:space:]]/ && index(line, subsec) != 1) { in_subsec=0 }
            if (in_subsec) {
                if (index(line, fld) == 1) {
                    val = substr(line, length(fld)+1)
                    gsub(/^[[:space:]]+/, "", val)
                    gsub(/[[:space:]]*#.*$/, "", val)
                    gsub(/^"/, "", val); gsub(/"$/, "", val)
                    gsub(/^'"'"'/, "", val); gsub(/'"'"'$/, "", val)
                    print val
                    exit
                }
            }
        }
    ' "$file" 2>/dev/null | head -1
}

# Two-level inline YAML list: ["-i", "~/.ssh/key"] → one element per line
_yaml_list() {
    local file="$1" section="$2" field="$3"
    local raw
    raw="$(_yaml_field "$file" "$section" "$field")"
    [[ -z "$raw" ]] && return 0
    echo "$raw" | sed 's/^\[//;s/\]$//;s/,[[:space:]]*/\n/g' | sed 's/^"//;s/"$//;s/^'"'"'//;s/'"'"'$//'
}

# Inline YAML list at three levels: section.subsection.field
_yaml_nested_list() {
    local file="$1" section="$2" subsection="$3" field="$4"
    [[ -f "$file" ]] || return 0
    local raw
    raw="$(_yaml_nested_field "$file" "$section" "$subsection" "$field")"
    [[ -z "$raw" ]] && return 0
    echo "$raw" | sed 's/^\[//;s/\]$//;s/,[[:space:]]*/\n/g' | sed 's/^"//;s/"$//;s/^'"'"'//;s/'"'"'$//'
}

# ── layered config accessors ────────────────────────────────────────────────

# Two-level: local > global > env > default
_config() {
    local section="$1" field="$2" envvar="${3:-}" default="${4:-}"
    local val=""

    if [[ -n "$LOCAL_CONFIG" ]]; then
        val="$(_yaml_field "$LOCAL_CONFIG" "$section" "$field")"
    fi
    if [[ -z "$val" ]] && [[ -f "$GLOBAL_CONFIG" ]]; then
        val="$(_yaml_field "$GLOBAL_CONFIG" "$section" "$field")"
    fi
    if [[ -z "$val" ]] && [[ -n "$envvar" ]] && [[ -n "${!envvar:-}" ]]; then
        val="${!envvar}"
    fi
    if [[ -z "$val" ]]; then
        val="$default"
    fi
    echo "${val/#\~/$HOME}"
}

# Three-level: local > global > env > default
_config_nested() {
    local section="$1" subsection="$2" field="$3" envvar="${4:-}" default="${5:-}"
    local val=""

    if [[ -n "$LOCAL_CONFIG" ]]; then
        val="$(_yaml_nested_field "$LOCAL_CONFIG" "$section" "$subsection" "$field")"
    fi
    if [[ -z "$val" ]] && [[ -f "$GLOBAL_CONFIG" ]]; then
        val="$(_yaml_nested_field "$GLOBAL_CONFIG" "$section" "$subsection" "$field")"
    fi
    if [[ -z "$val" ]] && [[ -n "$envvar" ]] && [[ -n "${!envvar:-}" ]]; then
        val="${!envvar}"
    fi
    if [[ -z "$val" ]]; then
        val="$default"
    fi
    echo "${val/#\~/$HOME}"
}

# Three-level list: local > global (first file wins)
_config_nested_list() {
    local section="$1" subsection="$2" field="$3"
    local val=""

    if [[ -n "$LOCAL_CONFIG" ]]; then
        val="$(_yaml_nested_list "$LOCAL_CONFIG" "$section" "$subsection" "$field")"
    fi
    if [[ -z "$val" ]] && [[ -f "$GLOBAL_CONFIG" ]]; then
        val="$(_yaml_nested_list "$GLOBAL_CONFIG" "$section" "$subsection" "$field")"
    fi
    echo "$val"
}
