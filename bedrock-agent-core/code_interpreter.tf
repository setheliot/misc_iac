# https://registry.terraform.io/providers/hashicorp/awscc/latest/docs/resources/bedrockagentcore_code_interpreter_custom

resource "awscc_bedrockagentcore_code_interpreter_custom" "python_interpreter" {
  name               = local.code_interpreter_name
  description        = "Secure Python code execution environment"
  execution_role_arn = aws_iam_role.code_interpreter.arn

  network_configuration = {
    network_mode = "SANDBOX"
  }

  tags = local.common_tags

  depends_on = [time_sleep.code_interpreter_iam_propagation]
}
