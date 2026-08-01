#!/usr/bin/env bash
#
# Create a ready-to-run iOS + macOS Granite application.
#
# Usage:
#   Scripts/create-granite-app.sh MyApp [options]
#
# Options:
#   --output PATH          Exact destination (default: sibling from Granite root)
#   --bundle-id ID         Bundle identifier (default: com.example.MyApp)
#   --display-name NAME    Name shown below the app icon (default: MyApp)
#   --team ID              Apple Developer team ID (optional)
#   --granite-path PATH    Local Granite checkout (default: this repository)
#   --copy-granite         Copy Granite into Packages/Granite and link it relatively
#   --no-open              Do not open the generated project in Xcode
#   -h, --help             Show this help
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="$REPO_ROOT/Resources/Templates/GraniteApp"
LOGO_PATH="$REPO_ROOT/Resources/GraniteIcon.png"

PROJECT_NAME=""
DESTINATION=""
BUNDLE_ID=""
DISPLAY_NAME=""
TEAM_ID=""
GRANITE_PATH="$REPO_ROOT"
COPY_GRANITE="no"
SHOULD_OPEN="yes"

if [ -t 1 ]; then
    BOLD="$(printf '\033[1m')"
    GREEN="$(printf '\033[32m')"
    YELLOW="$(printf '\033[33m')"
    RED="$(printf '\033[31m')"
    RESET="$(printf '\033[0m')"
else
    BOLD=""
    GREEN=""
    YELLOW=""
    RED=""
    RESET=""
    SHOULD_OPEN="no"
fi

info() { printf '%s\n' "$*"; }
ok() { printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*"; }
fail() {
    printf '%s✗%s %s\n' "$RED" "$RESET" "$*" 1>&2
    exit 1
}

usage() {
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

require_value() {
    option="$1"
    remaining="$2"
    value="${3:-}"
    if [ "$remaining" -lt 2 ] || [ -z "$value" ]; then
        fail "$option requires a value."
    fi
    case "$value" in
        --*) fail "$option requires a value." ;;
    esac
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output)
            require_value "$1" "$#" "${2:-}"
            DESTINATION="$2"
            shift 2
            ;;
        --bundle-id)
            require_value "$1" "$#" "${2:-}"
            BUNDLE_ID="$2"
            shift 2
            ;;
        --display-name)
            require_value "$1" "$#" "${2:-}"
            DISPLAY_NAME="$2"
            shift 2
            ;;
        --team)
            require_value "$1" "$#" "${2:-}"
            TEAM_ID="$2"
            shift 2
            ;;
        --granite-path)
            require_value "$1" "$#" "${2:-}"
            GRANITE_PATH="$2"
            shift 2
            ;;
        --copy-granite)
            COPY_GRANITE="yes"
            shift
            ;;
        --no-open)
            SHOULD_OPEN="no"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            fail "Unknown option: $1"
            ;;
        *)
            if [ -n "$PROJECT_NAME" ]; then
                fail "Only one project name can be supplied."
            fi
            PROJECT_NAME="$1"
            shift
            ;;
    esac
done

if [ -z "$PROJECT_NAME" ]; then
    if [ -t 0 ]; then
        printf 'Project name: '
        read -r PROJECT_NAME
    else
        usage
        fail "A project name is required."
    fi
fi

if [ "$(uname -s)" != "Darwin" ]; then
    fail "Granite app projects require macOS and Xcode 16 or newer."
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    fail "Xcode is required to create a Granite app project."
fi

XCODE_VERSION="$(xcodebuild -version | sed -n '1s/^Xcode //p')"
XCODE_MAJOR="${XCODE_VERSION%%.*}"
case "$XCODE_MAJOR" in
    ''|*[!0-9]*) fail "Could not determine the installed Xcode version." ;;
esac
if [ "$XCODE_MAJOR" -lt 16 ]; then
    fail "Xcode 16 or newer is required (found Xcode $XCODE_VERSION)."
fi

case "$PROJECT_NAME" in
    [A-Za-z]*) ;;
    *) fail "Project name must start with a letter and contain only letters and numbers." ;;
esac

case "$PROJECT_NAME" in
    *[!A-Za-z0-9]*) fail "Project name must start with a letter and contain only letters and numbers." ;;
esac

if [ -z "$BUNDLE_ID" ]; then
    BUNDLE_ID="com.example.$PROJECT_NAME"
fi

case "$BUNDLE_ID" in
    *[!A-Za-z0-9.-]*|.*|*..*|*.)
        fail "Bundle identifier must use reverse-DNS characters and cannot start/end with a period."
        ;;
esac

if [ -z "$DISPLAY_NAME" ]; then
    DISPLAY_NAME="$PROJECT_NAME"
fi

DISPLAY_INVALID="$(printf '%s' "$DISPLAY_NAME" | tr -d '[:alnum:] ._-')"
if [ -n "$DISPLAY_INVALID" ]; then
    fail "Display name contains unsupported characters."
fi

case "$TEAM_ID" in
    *[!A-Za-z0-9]*) fail "Developer team ID must contain only letters and numbers." ;;
esac
if [ -n "$TEAM_ID" ] && [ "${#TEAM_ID}" -ne 10 ]; then
    fail "Developer team ID must be exactly 10 characters."
fi

if [ -z "$DESTINATION" ]; then
    if [ "$PWD" = "$REPO_ROOT" ]; then
        DESTINATION="$(dirname "$REPO_ROOT")/$PROJECT_NAME"
    else
        DESTINATION="$PWD/$PROJECT_NAME"
    fi
fi

if [ ! -d "$TEMPLATE_DIR" ]; then
    fail "Project template not found: $TEMPLATE_DIR"
fi

if [ ! -f "$LOGO_PATH" ]; then
    fail "Granite logo not found: $LOGO_PATH"
fi

if [ ! -d "$GRANITE_PATH" ]; then
    fail "Granite checkout not found: $GRANITE_PATH"
fi

GRANITE_PATH="$(cd "$GRANITE_PATH" && pwd)"
if [ ! -f "$GRANITE_PATH/Package.swift" ]; then
    fail "The Granite path must contain Package.swift: $GRANITE_PATH"
fi

case "$GRANITE_PATH" in
    *\"*) fail "Granite path cannot contain a double quote." ;;
esac

GRANITE_REFERENCE="$GRANITE_PATH"
if [ "$COPY_GRANITE" = "yes" ]; then
    GRANITE_REFERENCE="Packages/Granite"
fi

CREATED_DESTINATION="no"
if [ -e "$DESTINATION" ]; then
    if [ ! -d "$DESTINATION" ]; then
        fail "Destination exists and is not a directory: $DESTINATION"
    fi
    if [ -n "$(ls -A "$DESTINATION")" ]; then
        fail "Destination is not empty: $DESTINATION"
    fi
else
    mkdir -p "$DESTINATION"
    CREATED_DESTINATION="yes"
fi

DESTINATION="$(cd "$DESTINATION" && pwd)"
case "$DESTINATION" in
    "$TEMPLATE_DIR"|"$TEMPLATE_DIR"/*)
        if [ "$CREATED_DESTINATION" = "yes" ]; then
            rmdir "$DESTINATION"
        fi
        fail "Destination cannot be inside the Granite app template."
        ;;
esac

escape_replacement() {
    printf '%s' "$1" \
        | sed -e 's/\\/\\\\/g' \
              -e 's/&/\\\&/g' \
              -e 's/|/\\|/g'
}

PROJECT_VALUE="$(escape_replacement "$PROJECT_NAME")"
BUNDLE_VALUE="$(escape_replacement "$BUNDLE_ID")"
DISPLAY_VALUE="$(escape_replacement "$DISPLAY_NAME")"
TEAM_VALUE="$(escape_replacement "$TEAM_ID")"
GRANITE_VALUE="$(escape_replacement "$GRANITE_REFERENCE")"

info "${BOLD}Creating $PROJECT_NAME${RESET}"
info "  destination: $DESTINATION"
info "  bundle id:   $BUNDLE_ID"
if [ "$COPY_GRANITE" = "yes" ]; then
    info "  Granite:     $GRANITE_PATH → $GRANITE_REFERENCE"
else
    info "  Granite:     $GRANITE_PATH"
fi

cp -R "$TEMPLATE_DIR/." "$DESTINATION/"
mv "$DESTINATION/GraniteApp.xcodeproj" "$DESTINATION/$PROJECT_NAME.xcodeproj"
mv "$DESTINATION/$PROJECT_NAME.xcodeproj/xcshareddata/xcschemes/GraniteApp-iOS.xcscheme" \
   "$DESTINATION/$PROJECT_NAME.xcodeproj/xcshareddata/xcschemes/$PROJECT_NAME-iOS.xcscheme"
mv "$DESTINATION/$PROJECT_NAME.xcodeproj/xcshareddata/xcschemes/GraniteApp-macOS.xcscheme" \
   "$DESTINATION/$PROJECT_NAME.xcodeproj/xcshareddata/xcschemes/$PROJECT_NAME-macOS.xcscheme"

while IFS= read -r -d '' file; do
    sed -e "s|__PROJECT_NAME__|$PROJECT_VALUE|g" \
        -e "s|__BUNDLE_ID__|$BUNDLE_VALUE|g" \
        -e "s|__DISPLAY_NAME__|$DISPLAY_VALUE|g" \
        -e "s|__TEAM_ID__|$TEAM_VALUE|g" \
        -e "s|__GRANITE_PATH__|$GRANITE_VALUE|g" \
        "$file" > "$file.granite-tmp"
    mv "$file.granite-tmp" "$file"
done < <(find "$DESTINATION" -type f \( \
    -name '*.swift' -o \
    -name '*.pbxproj' -o \
    -name '*.xcscheme' -o \
    -name '*.md' \
\) -print0)

cp "$LOGO_PATH" \
   "$DESTINATION/Shared/Assets.xcassets/GraniteLogo.imageset/GraniteLogo.png"

if [ "$COPY_GRANITE" = "yes" ]; then
    VENDORED_GRANITE="$DESTINATION/$GRANITE_REFERENCE"
    mkdir -p "$VENDORED_GRANITE"

    cp "$GRANITE_PATH/Package.swift" "$VENDORED_GRANITE/"
    cp -R "$GRANITE_PATH/Sources" "$VENDORED_GRANITE/"

    for item in Package.resolved LICENSE README.md Tests; do
        if [ -e "$GRANITE_PATH/$item" ]; then
            cp -R "$GRANITE_PATH/$item" "$VENDORED_GRANITE/"
        fi
    done
fi

ok "Created $PROJECT_NAME.xcodeproj"
if [ "$COPY_GRANITE" = "yes" ]; then
    ok "Copied Granite into $GRANITE_REFERENCE"
fi
ok "Added HomeComponent and SettingsComponent"
ok "Added EnvironmentService and persistent ConfigService"
ok "Added adaptive iPhone, iPad, and macOS navigation"

if [ "$SHOULD_OPEN" = "yes" ]; then
    if command -v open >/dev/null 2>&1 && open "$DESTINATION/$PROJECT_NAME.xcodeproj"; then
        ok "Opened the project in Xcode"
    else
        warn "The project was created, but Xcode could not be opened automatically."
        info "Open it with: open \"$DESTINATION/$PROJECT_NAME.xcodeproj\""
    fi
else
    info ""
    info "Open it with: open \"$DESTINATION/$PROJECT_NAME.xcodeproj\""
fi
