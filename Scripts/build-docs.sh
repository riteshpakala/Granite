#!/usr/bin/env bash
#
# build-docs.sh — build Granite's DocC documentation.
#
# Wraps the Swift-DocC plugin so documentation builds the same way in the terminal, in CI, and
# on a fresh machine — the package equivalent of a "Build Documentation" scheme.
#
# Usage:
#   Scripts/build-docs.sh [--target NAME] [--output DIR]      Build a .doccarchive (default).
#   Scripts/build-docs.sh --preview [--target NAME]           Serve live docs at localhost.
#   Scripts/build-docs.sh --static [--base-path NAME] [--output DIR]
#                                                             Emit static HTML for hosting
#                                                             (e.g. GitHub Pages) into DIR.
#   Scripts/build-docs.sh --help
#
# Options:
#   --target NAME     DocC target to build (default: Granite).
#   --output DIR      Output directory (default: .build/documentation, or ./docs for --static).
#   --base-path NAME  hosting-base-path for --static (default: the target name). Set this to your
#                     repo name when publishing to https://<user>.github.io/<repo>/.
#   --preview         Build and serve docs locally with live reload (Ctrl-C to stop).
#   --static          Transform output for static hosting.
#   --help            Show this help.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

TARGET="Granite"
OUTPUT=""
BASE_PATH=""
MODE="archive"   # archive | preview | static

if [ -t 1 ]; then
    BOLD="$(printf '\033[1m')"; GREEN="$(printf '\033[32m')"; RESET="$(printf '\033[0m')"
else
    BOLD=""; GREEN=""; RESET=""
fi
ok() { printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
err() { printf '✗ %s\n' "$*" 1>&2; }
usage() { sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --target)    TARGET="${2:?--target needs a value}"; shift ;;
        --output)    OUTPUT="${2:?--output needs a value}"; shift ;;
        --base-path) BASE_PATH="${2:?--base-path needs a value}"; shift ;;
        --preview)   MODE="preview" ;;
        --static)    MODE="static" ;;
        -h|--help)   usage; exit 0 ;;
        *) err "Unknown option: $1"; usage; exit 2 ;;
    esac
    shift
done

case "$MODE" in
    preview)
        printf '%sPreviewing docs for %s%s (Ctrl-C to stop)…\n' "$BOLD" "$TARGET" "$RESET"
        exec swift package --disable-sandbox preview-documentation --target "$TARGET"
        ;;

    static)
        OUTPUT="${OUTPUT:-$REPO_ROOT/docs}"
        BASE_PATH="${BASE_PATH:-$TARGET}"
        printf '%sBuilding static docs for %s%s → %s (base path: /%s/)\n' \
            "$BOLD" "$TARGET" "$RESET" "$OUTPUT" "$BASE_PATH"
        swift package --allow-writing-to-directory "$OUTPUT" \
            generate-documentation \
            --target "$TARGET" \
            --disable-indexing \
            --transform-for-static-hosting \
            --hosting-base-path "$BASE_PATH" \
            --output-path "$OUTPUT"
        ok "Static docs at $OUTPUT (serve or push to GitHub Pages)."
        ;;

    archive)
        OUTPUT="${OUTPUT:-$REPO_ROOT/.build/documentation}"
        printf '%sBuilding documentation archive for %s%s → %s\n' \
            "$BOLD" "$TARGET" "$RESET" "$OUTPUT"
        swift package --allow-writing-to-directory "$OUTPUT" \
            generate-documentation \
            --target "$TARGET" \
            --output-path "$OUTPUT"
        ok "Archive at $OUTPUT — open it with: open \"$OUTPUT\""
        ;;
esac
