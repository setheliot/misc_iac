# Bedrock AgentCore demo

Self-contained Terraform that provisions a complete AgentCore environment:

- One **CODE** runtime (Python) and one **CONTAINER** runtime (Docker / STRANDS)
- A **semantic memory** with one strategy
- An **MCP gateway** with a Lambda target
- A custom **browser** (used by the container agent's `browse` tool)
- A sandboxed **code interpreter**

The runtime source for both agents lives in `runtime-sources/`. The CONTAINER
agent reads memory and browser ARNs from `MEMORIES` / `BROWSERS` env vars
that this Terraform injects at deploy time.

## Differences from upstream

Forked from the AWS AgentCore Terraform Module
[examples](https://github.com/aws-ia/terraform-aws-agentcore/tree/main/examples),
particularly the [complete example](https://github.com/aws-ia/terraform-aws-agentcore/tree/main/examples/complete)
and its shared [container agent source](https://github.com/aws-ia/terraform-aws-agentcore/blob/main/examples/basic-container-runtime/src/app.py).
This version inlines and modifies the resources into one self-contained Terraform
root module. Both runtimes share an execution role; the other services retain
separate roles. The main differences are:

### Terraform and artifact updates

- **Local builds.** [Container](container_build.tf) and [CODE](code_build.tf)
  artifacts are built on your workstation and uploaded to ECR/S3, replacing
  upstream's [CodeBuild workflow](https://github.com/aws-ia/terraform-aws-agentcore/blob/main/codebuild.tf).
- **Content-based rebuilds.** One build ID per runtime hashes source filenames,
  contents, and its build script. Edits rebuild only the affected runtime;
  timestamps and unlisted files are ignored. See [Apply](#apply) for details.
- **Runtime and endpoint updates.** [runtime.tf](runtime.tf) uses build-ID image
  tags and S3 versions to deploy changes. Named endpoints follow new runtime versions
  instead of serving stale code. Endpoint version tracking is proposed upstream
  in [PR #31](https://github.com/aws-ia/terraform-aws-agentcore/pull/31) (not yet merged).
- **CloudWatch logging.** [iam.tf](iam.tf) uses the correct
  `/aws/bedrock-agentcore/*` log-group path so runtimes, browsers, and code
  interpreters can write logs. Proposed upstream in
  [PR #30](https://github.com/aws-ia/terraform-aws-agentcore/pull/30) (not yet merged).
- **Consistent Python packaging.** CODE dependencies target ARM64 and Python 3.11,
  regardless of the workstation's Python version.
- **Provider workaround and tests.** [versions.tf](versions.tf) pins `awscc` below
  `1.87.0` to avoid a gateway refresh issue.
  [Hash regression tests](tests/test_build_hashes.py) run locally without AWS.
- **Configuration and outputs.** Regional settings live in `environments/*.tfvars`;
  [outputs.tf](outputs.tf) exposes deployed IDs, ARNs, and URLs. Build artifacts go
  in `.terraform/tmp/`; upstream's `autogen/` helper files are not generated.

### Agent behavior

The changes below are implemented in
[runtime-sources/container-agent/app.py](runtime-sources/container-agent/app.py):

- **Live weather.** `weather(location)` replaces the upstream fixed sunny-weather
  response with Open-Meteo geocoding and current-weather requests. It accepts a
  location (default `Seattle, WA`) and reports conditions, temperature, feels-like
  temperature, humidity, and wind in Fahrenheit/mph. Requests use ten-second
  timeouts and return explanatory messages for unmatched locations or lookup
  failures. These requests do not use an API key.
- **Working browser tool.** `browse(url)` starts a session on the provisioned
  AgentCore browser, connects through Playwright over CDP, and returns up to
  4,000 characters of page text. It stops the session in `finally`; local Chromium
  installation is unnecessary.
- **Integrated memory and session continuity.** `AgentCoreMemorySessionManager`
  recalls an actor's facts before a turn and persists the conversation afterward.
  [memory.tf](memory.tf) uses `/facts/{actorId}/` to match retrieval configuration.
  The actor comes from payload `actor_id`; conversation continuity uses the
  runtime's `context.session_id`, including in the console playground. Without
  configured memory, the agent runs statelessly.
- **Stable resource lookup.** Terraform injects `MEMORIES` / `BROWSERS` JSON maps
  keyed by `semantic_memory` / `web_browser`. Python resolves their ARNs and
  derives service IDs, keeping lookups independent of AWS-assigned ID suffixes.
- **Configurable model and first-use subscription permissions.** `MODEL_ID`
  honors Terraform's `bedrock_model_id`, defaulting to the global Claude Sonnet
  4.5 inference profile. `temperature=0.1` and `max_tokens=2048` are passed as
  `BedrockModel` arguments instead of `additional_request_fields`.
  [iam.tf](iam.tf) adds Marketplace subscription
  visibility and permission to subscribe specifically to that model's product;
  review that permission when changing models.
- **Complete final-text handling.** Responses use `str(AgentResult)` rather than
  assuming the first content block contains the final answer, accommodating
  tool-use and reasoning blocks.

## Resource status

| Resource | Status |
| --- | --- |
| **CONTAINER** runtime | Active — STRANDS agent + Bedrock Claude with `browse`, `calculator`, live Open-Meteo `weather`, and `greeting` tools |
| Semantic memory | Active — long-term recall wired into CONTAINER via `AgentCoreMemorySessionManager` (Strands integration): auto-recalls the actor's facts before each turn and persists the conversation after |
| Custom browser | Used by CONTAINER (`browse` tool) |
| **CODE** runtime | Stub — no LLM, no tools, just echoes the prompt. Exists to demonstrate the zip / `PYTHON_3_11` deployment shape alongside the container shape |
| MCP gateway + Lambda target | Provisioned but no agent calls it |
| Code interpreter | Provisioned but no agent calls it |

### TODO

- Wire the **code interpreter** into the CONTAINER runtime as a `@tool`.
- Wire the **MCP gateway** into the CONTAINER runtime as a tool source, and have it call something meaningful
- Optionally, bring the CODE runtime up to a real agent (LLM + tools) so the demo shows both deployment shapes doing real work — not just contrasting how artifacts are packaged.


## Prerequisites

Runs on your workstation, not in CI. You need:

- AWS CLI v2 configured (`aws sts get-caller-identity` works)
- Terraform `>= 1.14`
- Bash 3.2 or newer (scripts can be launched from Bash or zsh on Linux/macOS)
- A running Docker daemon with `buildx` and an ARM64-capable builder
- Python 3 with `python3 -m pip` (used to install ARM64 wheels for the CODE runtime)
- `zip`

The [build scripts](scripts/) check required commands and report missing tools,
Docker/builder problems, and authentication failures. They use portable system
utilities and support paths containing spaces. Dependencies are not installed
automatically. Docker checks run only when an image actually needs building.

## Apply

```bash
terraform init
terraform plan -var-file=environments/us-east-1.tfvars
terraform apply -var-file=environments/us-east-1.tfvars
```

Terraform runs [build-container.sh](scripts/build-container.sh) and
[build-code.sh](scripts/build-code.sh) locally through `null_resource` during
`apply`. Each runtime has one SHA-256 build ID covering its selected source
filenames, file contents, and build script. Update `container_src_files` or
`code_src_files` when adding modules/data; keep the container list aligned with
the Dockerfile's `COPY` inputs. Recipe edits automatically change the build ID.
Timestamps, caches, and unlisted files are ignored; comments and whitespace in
listed inputs still count.

After applying, inspect the recorded build IDs with
`terraform output -raw container_build_id` and `terraform output -raw code_build_id`.

Container images use immutable `build-<build ID>` tags. The script reuses an
existing tag on retries or source reverts; otherwise it builds and pushes a new
image. The changed image URI updates the runtime. CODE uses the same build ID
for packaging and S3 `source_hash`, and the runtime references the uploaded ZIP's
S3 `version_id`. Packaging uses a temporary directory and replaces the local ZIP
only after success, preserving the previous ZIP on failure.

Unchanged inputs and configuration produce no builds or runtime versions.
Model/configuration changes can update a runtime without rebuilding. Changing
the ECR repository or CODE bucket triggers a build for the new destination.
Build IDs describe inputs, not reproducible dependency resolution: to refresh
dependencies deliberately, update their versions in `requirements.txt` or the
Dockerfile. Retained images are still subject to the ECR lifecycle policy.

AWS automatically moves `DEFAULT` to the latest runtime version. Terraform also
updates each named endpoint, reading its runtime version after the runtime update
completes to avoid the AWSCC provider's stale version value in the update plan.

Run local checks before deployment:

```bash
terraform fmt -check -recursive
terraform validate
bash -n scripts/build-container.sh scripts/build-code.sh
shellcheck scripts/build-container.sh scripts/build-code.sh
python3 -B -m unittest discover -s tests
```

ShellCheck is a development tool. Tests exercise real Terraform hashes and Bash
scripts with fake AWS/Docker/pip commands and real ZIP packaging, without AWS
calls or package downloads. To check another Bash version, set
`BASH_TEST_EXECUTABLE=/path/to/bash` when running the tests. Native macOS smoke
testing is recommended when changing shell commands.

## Inspecting memory

The CONTAINER agent wires AgentCore Memory into Strands via
`AgentCoreMemorySessionManager`, which recalls the actor's facts before each
turn and persists the conversation after. Facts are stored under
`/facts/{actorId}/`; `actor_id` comes from the invoke payload (default
`default-user`). Extraction is asynchronous, so recall can lag a minute or two.

```bash
aws bedrock-agentcore list-memory-records \
  --memory-id "$(terraform output -raw memory_id)" \
  --namespace "/facts/default-user/"
```

## Destroy

```bash
terraform destroy -var-file=environments/us-east-1.tfvars
```

ECR repos and S3 buckets have `force_delete`/`force_destroy` set, so destroy
works even with images/objects present.
