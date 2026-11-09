variable "idle_minutes" {
  description = "Tempo mínimo sem jogadores para parar a EC2."
  type        = number
  default     = 30
  validation {
    condition     = var.idle_minutes >= 10 && var.idle_minutes <= 1440 && floor(var.idle_minutes) == var.idle_minutes
    error_message = "Use de 10 a 1440 minutos inteiros."
  }
}

locals {
  control_name = "prominence-control-${aws_instance.server.id}"
}

resource "aws_ssm_document" "game_control" {
  name            = local.control_name
  document_type   = "Command"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Controle local de parada segura do Minecraft"
    parameters    = { mode = { type = "String", allowedValues = ["idle", "stop"] } }
    mainSteps = [{
      name   = "control"
      action = "aws:runShellScript"
      inputs = {
        timeoutSeconds = "360"
        runCommand     = ["mode='{{ mode }}'", "minutes=${var.idle_minutes}", file("${path.module}/automacao/controle-host.sh")]
      }
    }]
  })
}

resource "aws_iam_role" "control" {
  name_prefix = "prominence-control-"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_cloudwatch_log_group" "control" {
  name              = "/aws/lambda/${local.control_name}"
  retention_in_days = 7
}

resource "aws_iam_role_policy" "control" {
  role = aws_iam_role.control.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = "ec2:DescribeInstances", Resource = "*" },
      { Effect = "Allow", Action = "ec2:StartInstances", Resource = aws_instance.server.arn },
      { Effect = "Allow", Action = "ssm:SendCommand", Resource = [aws_instance.server.arn, aws_ssm_document.game_control.arn] },
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.control.arn}:*" }
    ]
  })
}

resource "aws_lambda_function" "control" {
  function_name    = local.control_name
  role             = aws_iam_role.control.arn
  handler          = "controle.handler"
  runtime          = "python3.13"
  timeout          = 30
  memory_size      = 128
  filename         = "${path.module}/automacao/controle.zip"
  source_code_hash = filebase64sha256("${path.module}/automacao/controle.zip")
  environment {
    variables = { INSTANCE_ID = aws_instance.server.id, CONTROL_DOCUMENT = aws_ssm_document.game_control.name }
  }
  depends_on = [aws_iam_role_policy.control]
}

resource "aws_cloudwatch_event_rule" "idle" {
  name_prefix         = "prominence-idle-"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_lambda_permission" "idle" {
  statement_id  = "IdleSchedule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.control.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.idle.arn
}

resource "aws_cloudwatch_event_target" "idle" {
  rule  = aws_cloudwatch_event_rule.idle.name
  arn   = aws_lambda_function.control.arn
  input = jsonencode({ action = "idle" })
  retry_policy {
    maximum_event_age_in_seconds = 60
    maximum_retry_attempts       = 0
  }
  depends_on = [aws_lambda_permission.idle]
}

output "control_function" { value = aws_lambda_function.control.function_name }
