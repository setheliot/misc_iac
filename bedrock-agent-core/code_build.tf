# This builds the CODE agent, which is only one of the agents in this repo

# Build flow: source hashes + build_script_hash -> build ID -> local ZIP -> versioned S3 object.
# Packaging runs on the workstation; runtime.tf deploys the uploaded ZIP version.
locals {
  code_src_dir      = "${path.module}/runtime-sources/code-agent"
  code_build_script = "${path.module}/scripts/build-code.sh"
  code_zip_path     = abspath("${path.module}/.terraform/tmp/code-agent.zip")

  # Use one source list for hashing and packaging; unlisted files are ignored.
  code_src_files = sort(["agent.py", "requirements.txt"])
  # Include filenames, source hashes, and build_script_hash to detect build input changes.
  code_build_id = sha256(jsonencode({
    sources           = { for f in local.code_src_files : f => filesha256("${local.code_src_dir}/${f}") }
    build_script_hash = filesha256(local.code_build_script)
  }))
}

# A changed trigger replaces this local build marker and reruns its provisioner.
resource "null_resource" "code_build" {
  triggers = {
    build_id = local.code_build_id
    # Recreate the local ZIP when a new destination needs an upload.
    bucket = aws_s3_bucket.code_runtime.id
  }

  # At apply time, the script installs Python 3.11 ARM64 wheels and creates the ZIP.
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "bash \"$BUILD_SCRIPT\""
    # Pass values as environment data so paths are not embedded in shell source.
    environment = {
      BUILD_SCRIPT       = abspath(local.code_build_script)
      BUILD_SOURCE_DIR   = abspath(local.code_src_dir)
      BUILD_ZIP_PATH     = local.code_zip_path
      BUILD_SOURCE_FILES = join("\n", local.code_src_files)
    }
  }
}

# Keep a stable S3 key; bucket versioning gives each upload a distinct version ID.
resource "aws_s3_object" "code_runtime_source" {
  bucket = aws_s3_bucket.code_runtime.id
  key    = "source.zip"
  source = local.code_zip_path

  # Track build inputs because the ZIP may not exist yet during planning.
  source_hash = local.code_build_id

  # Upload only after packaging finishes and S3 versioning is enabled.
  depends_on = [null_resource.code_build, aws_s3_bucket_versioning.code_runtime]
}
