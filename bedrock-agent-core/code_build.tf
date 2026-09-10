# CODE runtime build: pip install ARM64 wheels locally, zip, upload to S3.
# Replaces the module's CodeBuild flow.
#
# Requires python3 + pip on the workstation. The --platform/--python-version/
# --implementation/--abi/--only-binary flags pin pip to ARM64 cp311 wheels
# regardless of the host's Python version or architecture — AgentCore's CODE
# runtime is PYTHON_3_11 and rejects bytecode from other versions.

locals {
  code_src_dir   = "${path.module}/runtime-sources/code-agent"
  # abspath() — the build script `cd`s into $BUILD before zipping, so relative
  # paths from path.module no longer resolve correctly at that point.
  code_build_dir = abspath("${path.module}/.terraform/tmp/code-agent-build")
  code_zip_path  = abspath("${path.module}/.terraform/tmp/code-agent.zip")
  code_tmp_dir   = abspath("${path.module}/.terraform/tmp")

  code_src_hash = sha256(join("", [
    for f in sort(fileset(local.code_src_dir, "**")) :
    filesha256("${local.code_src_dir}/${f}")
  ]))

  # Bump when the build recipe (pip flags, post-processing) changes so the
  # local rebuild and S3 re-upload happen even if source files are unchanged.
  code_build_revision = "py311-v1"
}

resource "null_resource" "code_build" {
  triggers = {
    src_hash       = local.code_src_hash
    build_revision = local.code_build_revision
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      SRC='${local.code_src_dir}'
      BUILD='${local.code_build_dir}'
      ZIP='${local.code_zip_path}'

      rm -rf "$BUILD" "$ZIP"
      mkdir -p "$BUILD" '${local.code_tmp_dir}'
      cp -R "$SRC"/* "$BUILD/"

      if [ -f "$BUILD/requirements.txt" ]; then
        echo "Installing ARM64 cp311 wheels into $BUILD..."
        pip3 install -r "$BUILD/requirements.txt" \
          --target "$BUILD" \
          --platform manylinux2014_aarch64 \
          --python-version 3.11 \
          --implementation cp \
          --abi cp311 \
          --only-binary=:all: \
          --upgrade
        rm "$BUILD/requirements.txt"
      fi

      # Drop any __pycache__/.pyc — they're compiled against the host Python
      # version (e.g. 3.14) and AgentCore rejects bytecode that doesn't match
      # the runtime's 3.11 interpreter.
      find "$BUILD" -type d -name __pycache__ -exec rm -rf {} +
      find "$BUILD" -type f -name '*.pyc' -delete

      echo "Zipping to $ZIP..."
      (cd "$BUILD" && zip -qr "$ZIP" .)
      echo "Built $(wc -c < "$ZIP") bytes"
    EOT
  }
}

resource "aws_s3_object" "code_runtime_source" {
  bucket = aws_s3_bucket.code_runtime.id
  key    = "source.zip"
  source = local.code_zip_path
  # Include build_revision so a recipe change forces re-upload even when source
  # files are unchanged.
  etag = sha256("${local.code_src_hash}-${local.code_build_revision}")

  depends_on = [null_resource.code_build]
}
