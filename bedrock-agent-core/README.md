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

## Notes

Forked from the AWS AgentCore Terraform Module [examples](https://github.com/aws-ia/terraform-aws-agentcore/tree/main/examples). The upstream example *uses* the module; this version inlines (and modifies) enough of the module's internals that it no longer consumes the module. Notable divergences from the upstream:

- **Local builds, not CodeBuild.** Container and code-runtime artifacts are produced on the workstation via `null_resource` + `local-exec` — Docker buildx for the container image, `pip install --target` + `zip` for the code runtime.
- **Explicit cp311 / linux-arm64 pinning** in the code-runtime pip install, so the build doesn't depend on whatever Python the workstation happens to have (AgentCore's CODE runtime is fixed at `PYTHON_3_11`).
- **Logical-name env var injection.** Memory and browser ARNs are passed to the CONTAINER runtime via `MEMORIES` / `BROWSERS` JSON env vars keyed on stable names, so agent code looks up `memories["semantic_memory"]` instead of the per-deploy AWS-assigned ID suffix.


### Resource status

| Resource | Status |
| --- | --- |
| **CONTAINER** runtime | Active — STRANDS agent + Bedrock Claude with `browse`, `calculator`, `weather`, `greeting` tools |
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
