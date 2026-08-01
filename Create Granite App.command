#!/usr/bin/env bash
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATOR="$REPO_ROOT/Scripts/create-granite-app.sh"

cd "$REPO_ROOT" || exit 1

if [ "$#" -eq 0 ] && [ -t 0 ]; then
    project_name=""
    while [ -z "$project_name" ]; do
        printf 'Project name: '
        IFS= read -r project_name
    done

    default_projects_folder='~/Desktop'
    printf 'Projects folder [%s]: ' "$default_projects_folder"
    IFS= read -r projects_folder
    projects_folder="${projects_folder:-$default_projects_folder}"

    case "$projects_folder" in
        '~')
            projects_folder="$HOME"
            ;;
        '~/'*)
            projects_folder="$HOME/${projects_folder#\~/}"
            ;;
        /*)
            ;;
        *)
            projects_folder="$HOME/$projects_folder"
            ;;
    esac

    "$GENERATOR" "$project_name" \
        --output "$projects_folder/$project_name" \
        --copy-granite
else
    "$GENERATOR" "$@" --copy-granite
fi
status=$?

if [ "$status" -ne 0 ] && [ -t 0 ]; then
    printf '\nGeneration stopped. Press Return to close this window.'
    read -r _
fi

exit "$status"
