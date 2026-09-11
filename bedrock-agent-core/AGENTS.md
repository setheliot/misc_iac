# Repository Guidelines

## Project Structure & Module Organization

This Bedrock AgentCore demo is one Terraform root module with inlined resources. Read `README.md` for integration status.

| Files | Responsibility |
| --- | --- |
| `versions.tf`, `providers.tf`, `backend.tf` | Provider constraints, region, and state configuration |
| `variables.tf`, `locals.tf`, `environments/*.tfvars` | Inputs, stable names/tags, and regional settings |
| `runtime.tf` | PUBLIC CODE and CONTAINER runtimes and named endpoints |
| `memory.tf`, `browser.tf`, `code_interpreter.tf` | Semantic memory, PUBLIC browser, SANDBOX interpreter |
| `gateway.tf`, `lambda.tf` | IAM-authorized MCP gateway, Lambda target, and inline Node.js handler |
| `iam.tf` | Shared runtime role, other service roles, policies, propagation waits |
| `ecr.tf`, `s3.tf` | Immutable-tag ECR repository and versioned CODE artifact bucket |
| `container_build.tf`, `code_build.tf`, `outputs.tf` | Local builds/uploads and deployed IDs, ARNs, URLs |

- `runtime-sources/container-agent/`: Python Strands agent, dependencies, and ARM64 Dockerfile; integrates memory/browsing.
- `runtime-sources/code-agent/`: Python echo stub packaged as a ZIP for the CODE runtime.
- `scripts/build-container.sh`, `scripts/build-code.sh`: Bash 3.2-compatible build recipes with prerequisite checks.
- `tests/`: Terraform build-ID regression checks and script smoke tests using fake AWS/Docker/pip commands.
- `.terraform/tmp/`: generated packaging artifacts.

Neither agent calls the provisioned gateway or interpreter.

## Build, Test, and Development Commands

Run commands here. Deployment requires Terraform >= 1.14, configured AWS CLI v2, Bash >= 3.2, Docker daemon/buildx with ARM64 support, Python 3 with `python3 -m pip`, and `zip`. Check `aws sts get-caller-identity`. Builds need ECR, base-image registry, and package-repository access.

- `terraform init`: initialize providers and the configured backend.
- `terraform fmt -recursive`: format Terraform files; use `terraform fmt -check -recursive` to check formatting.
- `terraform validate`: validate configuration after initialization.
- `python3 -B -m unittest discover -s tests`: run local build-ID and script tests.
- `bash -n scripts/build-container.sh scripts/build-code.sh`: check script syntax.
- `shellcheck scripts/build-container.sh scripts/build-code.sh`: lint scripts (development dependency).
- `terraform plan -var-file=environments/us-east-1.tfvars`: review proposed infrastructure changes.
- `terraform apply -var-file=environments/us-east-1.tfvars`: build/upload changed artifacts and deploy.
- `terraform output`: inspect deployed identifiers and endpoints.

Use `us-west-2.tfvars` for that region. For the local echo server, install its requirements in a virtual environment, then run `python3 runtime-sources/code-agent/agent.py`.

## Build and Runtime Update Conventions

Builds use workstation `null_resource`/`local-exec` during apply, without CodeBuild.

- Each runtime has one build ID hashing relative source filenames, contents, and its build script. Recipe changes automatically trigger builds. Add modules/data to `container_src_files` or `code_src_files`; align container inputs with Dockerfile `COPY`. Unlisted files and timestamps are ignored.
- Container: build/push `linux/arm64` with `--provenance=false` under `build-<build ID>`. Reuse existing tags; do not overwrite them. The image URI drives runtime updates. `container_image_tag` and `CONTAINER_SOURCE_HASH` have been removed.
- CODE: package Python 3.11 ARM64 wheels with `python3 -m pip`, remove bytecode, and atomically replace the ZIP. Use `code_build_id` directly as S3 `source_hash` and retain the runtime's S3 `version_id`. No manual recipe revision is needed.
- Preserve named endpoints and the data-source dependencies that read runtime versions after updates. Keep `null_resource` addresses stable. Check the README migration/recovery notes before forcing a build.
- Keep scripts compatible with Bash 3.2 and BSD/GNU utilities; quote paths, check dependencies before builds, and clean staging directories on failure. Pass Terraform values through the provisioner's environment rather than interpolating shell commands.

## Coding Style & Naming Conventions

Use two-space Terraform indentation and `terraform fmt`; four-space Python indentation, `snake_case` functions, and uppercase constants. Follow surrounding style; no Python formatter/linter is configured.

Keep `MEMORIES`/`BROWSERS` keys (`semantic_memory`, `web_browser`) aligned with Python lookups and `/facts/{actorId}/` aligned with memory configuration. Retain IAM propagation waits. Preserve `awscc < 1.87.0` until the gateway refresh issue in `versions.tf` is verified fixed. When changing `bedrock_model_id`, review product-scoped Marketplace permissions in `iam.tf`.

## Testing Guidelines

Use `unittest`, `test_*.py` files, and `test_*` methods. Tests need Terraform, Bash, Python, `zip`, and standard filesystem utilities; they make no AWS calls or package downloads. Extend them for build inputs, recipe edits, renamed files, dependency failures, cleanup, and retry behavior. Set `BASH_TEST_EXECUTABLE` to test another Bash version. No coverage threshold is configured. Report actual OS/shell coverage and distinguish local checks from deployment/invocation checks.

## Commit & Pull Request Guidelines

Use focused commits with short descriptive summaries, usually lowercase without fixed prefixes. PRs should explain behavior changes, affected resources, validation, relevant plan output, and related issues.

## Configuration & State

State defaults to local; the S3 backend is commented out. Keep state, plans, and `.terraform/` artifacts uncommitted; retain the ignored lockfile convention. Verify account, region, and state before deployment: regional variable files do not isolate state. ECR `force_delete`/S3 `force_destroy` allow artifact deletion during destroy. Documentation/local validation does not require deployment.
