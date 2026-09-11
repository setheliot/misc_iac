# https://registry.terraform.io/providers/hashicorp/awscc/latest/docs/data-sources/bedrockagentcore_memory

resource "awscc_bedrockagentcore_memory" "semantic_memory" {
  name                      = local.memory_name
  description               = "Semantic memory for factual knowledge"
  event_expiry_duration     = 90
  memory_execution_role_arn = aws_iam_role.memory.arn

  memory_strategies = [
    {
      semantic_memory_strategy = {
        name        = "semantic_facts"
        description = "Extract factual knowledge from conversations"
        # Actor-scoped (not strategy-scoped) so the same namespace string can be
        # referenced verbatim in the agent's retrieval_config — only {actorId}
        # needs substitution, which AgentCoreMemorySessionManager fills in.
        namespaces = ["/facts/{actorId}/"]
      }
    },
  ]

  tags = local.common_tags

  depends_on = [time_sleep.memory_iam_propagation]
}
