#!/usr/bin/env bash
# Bash 3.2+ (macOS/Linux). Inputs are passed through local-exec's environment.
set -euo pipefail

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command '$1' is missing. $2"
}

: "${BUILD_SOURCE_DIR:?Set BUILD_SOURCE_DIR to the container source directory.}"
: "${BUILD_REPOSITORY_URL:?Set BUILD_REPOSITORY_URL to the ECR repository URL.}"
: "${BUILD_IMAGE_TAG:?Set BUILD_IMAGE_TAG to the build ID tag.}"
: "${BUILD_AWS_REGION:?Set BUILD_AWS_REGION to the ECR region.}"
[[ -f "$BUILD_SOURCE_DIR/Dockerfile" ]] || fail "No Dockerfile in $BUILD_SOURCE_DIR."
require_command aws "Install AWS CLI v2 and configure AWS access."

registry=${BUILD_REPOSITORY_URL%%/*}
repository=${BUILD_REPOSITORY_URL#*/}
[[ "$registry" != "$repository" ]] || fail "Expected an ECR registry/repository URL."
image_uri="$BUILD_REPOSITORY_URL:$BUILD_IMAGE_TAG"

# Only ImageNotFound means 'build it'. Authentication/network failures must stop.
image_exists() {
    local response
    if response=$(aws ecr describe-images \
        --repository-name "$repository" \
        --image-ids "imageTag=$BUILD_IMAGE_TAG" \
        --region "$BUILD_AWS_REGION" --no-cli-pager \
        --query 'imageDetails[0].imageDigest' --output text 2>&1); then
        [[ "$response" == sha256:* ]] || fail "ECR returned no digest for $image_uri."
        return 0
    fi
    case "$response" in
        *'(ImageNotFoundException)'*) return 1 ;;
        *) fail "Cannot inspect $image_uri. Check AWS access and region. $response" ;;
    esac
}

# Retries and source reverts reuse a published build instead of overwriting it.
if image_exists; then
    printf 'Using existing image %s\n' "$image_uri"
    exit 0
fi

require_command docker "Install Docker Desktop on macOS or Docker Engine on Linux."
require_command sleep "Install the standard system utilities."
docker info >/dev/null 2>&1 || fail "Docker daemon is unavailable. Start Docker and check socket access."
docker buildx version >/dev/null 2>&1 || fail "Docker buildx is unavailable. Install or enable the buildx plugin."
if ! builder_info=$(docker buildx inspect --bootstrap 2>&1); then
    fail "Cannot start the selected buildx builder. $builder_info"
fi
case "$builder_info" in
    *linux/arm64*) ;;
    *) fail "The selected buildx builder lacks linux/arm64 support. Use Docker Desktop, an ARM64 builder, or configure emulation." ;;
esac

printf 'Logging in to ECR...\n'
if ! aws ecr get-login-password --region "$BUILD_AWS_REGION" --no-cli-pager \
    | docker login --username AWS --password-stdin "$registry"; then
    fail "ECR login failed. Check AWS credentials and ECR permissions."
fi

printf 'Building %s for linux/arm64...\n' "$image_uri"
docker buildx build --platform linux/arm64 --provenance=false \
    --tag "$image_uri" --push "$BUILD_SOURCE_DIR" \
    || fail "Container build or ECR push failed."

for ((attempt = 1; attempt <= 30; attempt++)); do
    if image_exists; then
        printf 'Image available: %s\n' "$image_uri"
        exit 0
    fi
    sleep 2
done
fail "Image was not visible in ECR after 60 seconds: $image_uri"
