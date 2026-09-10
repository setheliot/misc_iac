# https://registry.terraform.io/providers/hashicorp/awscc/latest/docs/data-sources/bedrockagentcore_browser_custom

resource "awscc_bedrockagentcore_browser_custom" "web_browser" {
  name               = local.browser_name
  description        = "Custom browser for web interaction"
  execution_role_arn = aws_iam_role.browser.arn

  network_configuration = {
    network_mode = "PUBLIC"
  }

  tags = local.common_tags

  depends_on = [time_sleep.browser_iam_propagation]
}
