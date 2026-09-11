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
| `ecr.tf`, `s3.tf` | Mutable-tag ECR repository and versioned CODE artifact bucket |
| `container_build.tf`, `code_build.tf`, `outputs.tf` | Local builds/uploads and deployed IDs, ARNs, URLs |

- `runtime-sources/container-agent/`: Python Strands agent, dependencies, and ARM64 Dockerfile; integrates memory/browsing.
- `runtime-sources/code-agent/`: Python echo stub packaged as a ZIP for the CODE runtime.
- `tests/test_build_hashes.py`: regression checks for Terraform build fingerprints.
- `.terraform/tmp/`: generated packaging artifacts.

Neither agent calls the provisioned gateway or interpreter.

## Build, Test, and Development Commands

Run commands here. Deployment requires Terraform >= 1.14, configured AWS CLI access, Bash, Docker daemon/buildx with ARM64 support, Python 3/`pip3`, and `zip`. Check `aws sts get-caller-identity`. Builds need ECR, base-image registry, and package-repository access.

- `terraform init`: initialize providers and the configured backend.
- `terraform fmt -recursive`: format Terraform files; use `terraform fmt -check -recursive` to check formatting.
- `terraform validate`: validate configuration after initialization.
- `python3 -B -m unittest discover -s tests`: run local hash regression tests.
- `terraform plan -var-file=environments/us-east-1.tfvars`: review proposed infrastructure changes.
- `terraform apply -var-file=environments/us-east-1.tfvars`: build/upload changed artifacts and deploy.
- `terraform output`: inspect deployed identifiers and endpoints.

Use `us-west-2.tfvars` for that region. For the local echo server, install its requirements in a virtual environment, then run `python3 runtime-sources/code-agent/agent.py`.

## Build and Runtime Update Conventions

Builds use workstation `null_resource`/`local-exec` during apply, without CodeBuild.

- Container: pipe `aws ecr get-login-password` to `docker login --username AWS --password-stdin`; build with `docker buildx build --platform linux/arm64 --provenance=false --tag ... --push`, then poll ECR. The image uses Amazon Linux 2023/Python 3.11. Source content, repository URL, or tag changes trigger rebuilding.
- CODE: copy `code_src_files`, install binary `manylinux2014_aarch64`/CPython 3.11 wheels with `pip3 install --target`, remove bytecode, ZIP under `.terraform/tmp/`, and upload versioned `source.zip` to S3. Preserve platform/ABI flags and absolute build paths.
- Add modules/data to `container_src_files` or `code_src_files`; align container inputs with Dockerfile `COPY`. Bump `code_build_revision` for CODE packaging-recipe changes. Hashes ignore unlisted files and timestamps; listed-file whitespace changes still count.
- Preserve `CONTAINER_SOURCE_HASH`, CODE S3 `source_hash`/`version_id`, and endpoint data-source dependencies in `runtime.tf`: these trigger runtime updates and move named endpoints to the updated versions.

## Coding Style & Naming Conventions

Use two-space Terraform indentation and `terraform fmt`; four-space Python indentation, `snake_case` functions, and uppercase constants. Follow surrounding style; no Python formatter/linter is configured.

Keep `MEMORIES`/`BROWSERS` keys (`semantic_memory`, `web_browser`) aligned with Python lookups and `/facts/{actorId}/` aligned with memory configuration. Retain IAM propagation waits. Preserve `awscc < 1.87.0` until the gateway refresh issue in `versions.tf` is verified fixed. When changing `bedrock_model_id`, review product-scoped Marketplace permissions in `iam.tf`.

## Testing Guidelines

Use `unittest`, `test_*.py` files, and `test_*` methods. Hash tests require Terraform without providers/AWS calls. Extend them for build-input/fingerprint changes. No coverage threshold is configured. Report checks run; distinguish local validation from deployment/invocation checks.

## Commit & Pull Request Guidelines

Use focused commits with short descriptive summaries, usually lowercase without fixed prefixes. PRs should explain behavior changes, affected resources, validation, relevant plan output, and related issues.

## Configuration & State

State defaults to local; the S3 backend is commented out. Keep state, plans, and `.terraform/` artifacts uncommitted; retain the ignored lockfile convention. Verify account, region, and state before deployment: regional variable files do not isolate state. ECR `force_delete`/S3 `force_destroy` allow artifact deletion during destroy. Documentation/local validation does not require deployment.
