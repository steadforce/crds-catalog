#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <name>"
    exit 1
fi
NAME="$1"

CONFIG_FILE="crds-catalog-config.yaml"

SOURCE_CONFIG=$(yq eval '.sources[] | select(.name == "'$NAME'") // ""' "$CONFIG_FILE")
if [ -z "$SOURCE_CONFIG" ]; then
    echo "Source with name '$NAME' not found in $CONFIG_FILE"
    exit 1
fi

REPOSITORY=$(echo "$SOURCE_CONFIG" | yq eval '.repository' -)
VERSION=$(echo "$SOURCE_CONFIG" | yq eval '.version' -)
FILES=$(echo "$SOURCE_CONFIG" | yq eval '.files' -)

echo "Updating CRDs for: $NAME"
echo "- Repository: $REPOSITORY"
echo "- Version: $VERSION"
echo "- Files: $FILES"
echo ""

if [ -z "$RUNNER_TEMP" ]; then
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf -- "$TMP_DIR"' EXIT
else
    TMP_DIR="$RUNNER_TEMP"
fi

# ORIGINAL_DIR=$(pwd)
REPO_DIR=$TMP_DIR/$(basename "$REPOSITORY" .git)

# Clone repo to temp dir
git clone "$REPOSITORY" "$REPO_DIR"
git -C "$REPO_DIR" fetch --all
git -C "$REPO_DIR" checkout "$VERSION"

shopt -s extglob
shopt -s nullglob

# Preprocess with helm if enabled in config (set `helm: true` on a source)
HELM_ENABLED=$(echo "$SOURCE_CONFIG" | yq eval '.helm // "false"' -)
RENDERED_INPUT=""
if [ "$HELM_ENABLED" = "true" ]; then
    echo "Helm preprocessing enabled — rendering charts"
    RENDERED_FILE="$TMP_DIR/${NAME}-rendered.yaml"
    : > "$RENDERED_FILE"
    # Iterate matched chart paths and skip non-directories
    for path in $REPO_DIR/$FILES; do
        if [ -d "$path" ]; then
            echo "Rendering chart: $path"
            helm template "$NAME" "$path" --include-crds >> "$RENDERED_FILE" || {
                echo "helm template failed for $path"
                exit 1
            }
        fi
    done
    RENDERED_INPUT="$RENDERED_FILE"
fi

# Download converter script
curl https://raw.githubusercontent.com/yannh/kubeconform/master/scripts/openapi2jsonschema.py --output $TMP_DIR/openapi2jsonschema.py 2>/dev/null

# Setup python venv
VENV_DIR="$TMP_DIR/.venv"
python3 -m venv "$VENV_DIR"
. "$VENV_DIR/bin/activate"
python -m pip install --upgrade pip
python -m pip install pyyaml

# Convert crds to json schema
export FILENAME_FORMAT="{fullgroup}__{kind}_{version}"
if [ -z "$RENDERED_INPUT" ]; then
    python $TMP_DIR/openapi2jsonschema.py $REPO_DIR/$FILES
else
    python $TMP_DIR/openapi2jsonschema.py $RENDERED_INPUT
fi

# Move files to group folders
for schema in *__*.json; do
    base=$(basename "$schema" .json)
    IFS='__' read -r group kind_version <<< "$base"
    mkdir -p "$group"
    kind_version="${kind_version#_}"
    mv "$schema" "$group/${kind_version}.json"
done

# Clean up in case of local temp dir
if [ -z "$RUNNER_TEMP" ]; then
    ls -la "$TMP_DIR"
    echo "Cleaning up temp dir $TMP_DIR"
    rm -rf "$TMP_DIR"
fi
