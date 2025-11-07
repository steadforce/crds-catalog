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
python $TMP_DIR/openapi2jsonschema.py $REPO_DIR/$FILES

# Move files to group folders
shopt -s nullglob
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
