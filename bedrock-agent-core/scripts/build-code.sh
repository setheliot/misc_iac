#!/usr/bin/env bash
# Bash 3.2+ (macOS/Linux). BUILD_SOURCE_FILES contains one relative path per line.
set -euo pipefail

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

: "${BUILD_SOURCE_DIR:?Set BUILD_SOURCE_DIR to the CODE source directory.}"
: "${BUILD_ZIP_PATH:?Set BUILD_ZIP_PATH to the output ZIP path.}"
: "${BUILD_SOURCE_FILES:?Set BUILD_SOURCE_FILES to the files to package, one per line.}"

for dependency in python3 zip mktemp mkdir cp mv rm find dirname; do
    command -v "$dependency" >/dev/null 2>&1 \
        || fail "Required command '$dependency' is missing. Install it before packaging."
done
python3 -m pip --version >/dev/null 2>&1 \
    || fail "pip is unavailable for python3. Install pip for that interpreter (or use a virtual environment)."
[[ -d "$BUILD_SOURCE_DIR" ]] || fail "Source directory does not exist: $BUILD_SOURCE_DIR"

# Validate every input before creating a staging directory or touching the ZIP.
while IFS= read -r source_file; do
    case "$source_file" in
        ''|/*|..|../*|*/../*|*/..) fail "Expected a relative source file: $source_file" ;;
    esac
    [[ -f "$BUILD_SOURCE_DIR/$source_file" ]] || fail "Missing source file: $source_file"
done <<< "$BUILD_SOURCE_FILES"

output_dir=$(dirname "$BUILD_ZIP_PATH")
mkdir -p "$output_dir"
# An explicit template works with both BSD and GNU mktemp. Stage beside the ZIP
# so publishing with mv is atomic and a failed build preserves the previous ZIP.
build_temp_dir=$(mktemp -d "$output_dir/.code-agent.XXXXXX")
build_temp_dir=$(cd "$build_temp_dir" && pwd -P)
trap 'rm -rf "$build_temp_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
package_dir="$build_temp_dir/package"
mkdir "$package_dir"

while IFS= read -r source_file; do
    mkdir -p "$package_dir/$(dirname "./$source_file")"
    cp "$BUILD_SOURCE_DIR/$source_file" "$package_dir/$source_file"
done <<< "$BUILD_SOURCE_FILES"

# Add the necessary requirements to the package directory
if [[ -f "$package_dir/requirements.txt" ]]; then
    printf 'Installing Python 3.11 ARM64 wheels...\n'
    python3 -m pip install -r "$package_dir/requirements.txt" \
        --target "$package_dir" \
        --platform manylinux2014_aarch64 \
        --python-version 3.11 --implementation cp --abi cp311 \
        --only-binary=:all: --no-compile --upgrade \
        || fail "Dependency installation failed. Check package access and Python 3.11 ARM64 wheel availability."
    rm "$package_dir/requirements.txt"
fi

# Remove host-generated or bundled bytecode before uploading to PYTHON_3_11.
find "$package_dir" -type d -name __pycache__ -prune -exec rm -rf {} +
find "$package_dir" -type f -name '*.pyc' -exec rm -f {} +
# Build the ZIP with agent.py and its installed dependencies at the archive root.
# Terraform uploads this archive to S3 as source.zip (see code_build.tf).
(cd "$package_dir" && zip -qr "$build_temp_dir/source.zip" .) \
    || fail "ZIP packaging failed."
mv "$build_temp_dir/source.zip" "$BUILD_ZIP_PATH"
printf 'Built %s\n' "$BUILD_ZIP_PATH"
