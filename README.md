# Miscellaneous IaC Workloads for AWS
Catch-all bin for various workloads defined using Infrastructure as Code (IaC)

Feel free to use these are you wish 😁

## Projects

Each project has its own README with setup instructions. Terraform demos share application code where appropriate.

| Project | Description |
| --- | --- |
| [bedrock-agent-core](bedrock-agent-core/README.md) | AgentCore demo with a Strands container agent, a Python echo runtime, semantic memory, and browser integration. |
| [guestbook-app](guestbook-app/README.md) | Shared Flask guestbook app, with Lambda and Kubernetes container images, build helpers, and offline tests. |
| [lambda-container](lambda-container/README.md) | Terraform deployment of the shared guestbook on ARM64 Lambda, API Gateway, and DynamoDB. |
| [redshift](redshift/README.md) | Provisioned Redshift cluster with VPC networking, encryption, logging, snapshot copying, and scheduled actions. |
| [redshift-serverless](redshift-serverless/README.md) | Redshift Serverless namespace and workgroup with VPC networking, encryption, and a managed endpoint. |

If you are looking for an EKS workload, including a functional sample application, see this: https://github.com/setheliot/eks_demo
