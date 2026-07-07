#!/usr/bin/env bash
#
# install-templates.sh — install Granite's Xcode file templates on this machine.
#
# Copies (or symlinks) the .xctemplate bundles from Resources/Templates/XCTemplates into
# Xcode's user template directory so "File ▸ New ▸ File…" offers a "Granite" section with
# Component, Service, and Reducer templates.
#
# Usage:
#   Scripts/install-templates.sh [--symlink] [--force] [--uninstall] [--help]
#
#   --symlink     Symlink the templates instead of copying (edits in the repo take effect
#                 live — handy when developing Granite itself).
#   --force       Overwrite existing installed templates without prompting.
#   --uninstall   Remove the installed Granite templates and exit.
#   --help        Show this help.
#
set -euo pipefail

# --- Resolve paths -----------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$REPO_ROOT/Resources/Templates/XCTemplates"
DEST_DIR="$HOME/Library/Developer/Xcode/Templates/Granite"

MODE="copy"
FORCE="no"
ACTION="install"

# --- Pretty output -----------------------------------------------------------------------
if [ -t 1 ]; then
    BOLD="$(printf '\033[1m')"; GREEN="$(printf '\033[32m')"; YELLOW="$(printf '\033[33m')"
    RED="$(printf '\033[31m')"; RESET="$(printf '\033[0m')"
else
    BOLD=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi
info()  { printf '%s\n' "$*"; }
ok()    { printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn()  { printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*"; }
err()   { printf '%s✗%s %s\n' "$RED" "$RESET" "$*" 1>&2; }

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; }

# --- Parse arguments ---------------------------------------------------------------------
while [ "$#" -gt 0 ]; do
    case "$1" in
        --symlink)   MODE="symlink" ;;
        --force)     FORCE="yes" ;;
        --uninstall) ACTION="uninstall" ;;
        -h|--help)   usage; exit 0 ;;
        *) err "Unknown option: $1"; usage; exit 2 ;;
    esac
    shift
done

# --- Guards ------------------------------------------------------------------------------
if [ "$(uname -s)" != "Darwin" ]; then
    err "Xcode templates are only supported on macOS."
    exit 1
fi

# --- Uninstall ---------------------------------------------------------------------------
if [ "$ACTION" = "uninstall" ]; then
    if [ -e "$DEST_DIR" ] || [ -L "$DEST_DIR" ]; then
        rm -rf "$DEST_DIR"
        ok "Removed $DEST_DIR"
    else
        info "Nothing to remove ($DEST_DIR does not exist)."
    fi
    exit 0
fi

# --- Install -----------------------------------------------------------------------------
if [ ! -d "$SRC_DIR" ]; then
    err "Template source not found: $SRC_DIR"
    exit 1
fi

shopt -s nullglob
TEMPLATES=("$SRC_DIR"/*.xctemplate)
shopt -u nullglob
if [ "${#TEMPLATES[@]}" -eq 0 ]; then
    err "No .xctemplate bundles found in $SRC_DIR"
    exit 1
fi

info "${BOLD}Installing Granite Xcode templates${RESET}"
info "  from: $SRC_DIR"
info "  to:   $DEST_DIR"
info "  mode: $MODE"

mkdir -p "$DEST_DIR"

installed=0
for template in "${TEMPLATES[@]}"; do
    name="$(basename "$template")"
    target="$DEST_DIR/$name"

    if [ -e "$target" ] || [ -L "$target" ]; then
        if [ "$FORCE" = "yes" ]; then
            rm -rf "$target"
        else
            warn "Skipping $name (already installed — use --force to overwrite)"
            continue
        fi
    fi

    if [ "$MODE" = "symlink" ]; then
        ln -s "$template" "$target"
    else
        cp -R "$template" "$target"
    fi
    ok "$name"
    installed=$((installed + 1))
done

info ""
ok "${BOLD}Done.${RESET} Installed $installed template(s)."
info "Restart Xcode, then use File ▸ New ▸ File… and pick the ${BOLD}Granite${RESET} section."
