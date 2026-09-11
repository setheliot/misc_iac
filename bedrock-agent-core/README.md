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
- **Content-based rebuilds.** SHA-256 hashes track selected source files, so edits
  rebuild only the affected runtime. Timestamps and unlisted files are ignored.
  See [Apply](#apply) for build inputs and packaging-recipe changes.
- **Runtime and endpoint updates.** [runtime.tf](runtime.tf) tracks source hashes
  and S3 versions to deploy changes. Named endpoints follow new runtime versions
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

- AWS CLI configured (`aws sts get-caller-identity` works)
- Terraform `>= 1.14`
- Docker with `buildx` (the container build pushes `linux/arm64` images)
- Python 3 + `pip` (used to install ARM64 wheels for the CODE runtime)
- `zip`

## Apply

```bash
terraform init
terraform apply -var-file=environments/us-east-1.tfvars
```

Container builds and code-runtime pip installs run locally via `null_resource`
during `apply`. Content changes to the inputs listed in `container_src_files`
or `code_src_files` trigger the corresponding build. Update those lists when
adding application modules or data, and keep the container list aligned with
the Dockerfile's `COPY` inputs. Caches, editor files, and documentation outside
these lists do not trigger builds. Comments and whitespace within listed files
still count as content changes.

The container source hash triggers a runtime version after the image is pushed.
The CODE runtime references the uploaded ZIP's S3 version. Unchanged inputs and
configuration produce no new builds or runtime versions; changing deployment
configuration (such as the model ID) can still require a runtime version. Changing
the ECR destination/tag or `code_build_revision` deliberately triggers a build.

AWS automatically moves `DEFAULT` to the latest runtime version. Terraform also
updates each named endpoint, reading its runtime version after the runtime update
completes to avoid the AWSCC provider's stale version value in the update plan.

Run the local hash regression checks with `python3 -B -m unittest discover -s tests`.

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
