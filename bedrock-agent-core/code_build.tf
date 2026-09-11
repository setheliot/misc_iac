# Local Python 3.11/ARM64 packaging. S3 versions identify the uploaded artifact.
locals {
  code_src_dir      = "${path.module}/runtime-sources/code-agent"
  code_build_script = "${path.module}/scripts/build-code.sh"
  code_zip_path     = abspath("${path.module}/.terraform/tmp/code-agent.zip")

  # Hash and package the same inputs, including relative names for rename detection.
  code_src_files = sort(["agent.py", "requirements.txt"])
  code_build_id = sha256(jsonencode({
    sources = { for f in local.code_src_files : f => filesha256("${local.code_src_dir}/${f}") }
    recipe  = filesha256(local.code_build_script)
  }))
}

resource "null_resource" "code_build" {
  triggers = {
    build_id = local.code_build_id
    # Recreate the local ZIP when a new destination needs an upload.
    bucket = aws_s3_bucket.code_runtime.id
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "bash \"$BUILD_SCRIPT\""
    environment = {
      BUILD_SCRIPT       = abspath(local.code_build_script)
      BUILD_SOURCE_DIR   = abspath(local.code_src_dir)
      BUILD_ZIP_PATH     = local.code_zip_path
      BUILD_SOURCE_FILES = join("\n", local.code_src_files)
    }
  }
}

resource "aws_s3_object" "code_runtime_source" {
  bucket      = aws_s3_bucket.code_runtime.id
  key         = "source.zip"
  source      = local.code_zip_path
  source_hash = local.code_build_id

  depends_on = [null_resource.code_build, aws_s3_bucket_versioning.code_runtime]
}
