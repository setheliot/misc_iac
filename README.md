# Miscellaneous IaC Workloads for AWS
Catch-all bin for various workloads defined using Infrastructure as Code (IaC)

Feel free to use these are you wish 😁

## Projects

Each directory is a separate Terraform project. Follow its README for setup and deployment instructions.

| Project | Description |
| --- | --- |
| [bedrock-agent-core](bedrock-agent-core/README.md) | AgentCore demo with a Strands container agent, a Python echo runtime, semantic memory, and browser integration. |
| [lambda-container](lambda-container/README.md) | Container-based Lambda guestbook application using API Gateway and DynamoDB. |
| [redshift](redshift/README.md) | Provisioned Redshift cluster with VPC networking, encryption, logging, snapshot copying, and scheduled actions. |
| [redshift-serverless](redshift-serverless/README.md) | Redshift Serverless namespace and workgroup with VPC networking, encryption, and a managed endpoint. |

If you are looking for an EKS workload, including a functional sample application, see this: https://github.com/setheliot/eks_demo
