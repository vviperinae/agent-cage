variable "name" {
  type    = string
  default = "agent-cage"
}

variable "agent_role_name" {
  type = string
}

variable "agent_role_arn" {
  type = string
}

variable "alarm_name" {
  type = string
}

data "aws_caller_identity" "current" {}

# ---------- CloudTrail ----------
resource "aws_s3_bucket" "trail" {
  #checkov:skip=CKV2_AWS_62:No event-driven processing in this lab
  #checkov:skip=CKV_AWS_18:Access logging is out of scope for this lab
  #checkov:skip=CKV_AWS_144:Cross-region replication is unnecessary for a disposable lab
  #checkov:skip=CKV_AWS_145:Default SSE-S3 encryption is enabled; a KMS key adds cost and complexity for a lab
  bucket        = "${var.name}-trail-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket                  = aws_s3_bucket.trail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "trail" {
  bucket = aws_s3_bucket.trail.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {}

    expiration {
      days = 30
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "trail_bucket" {
  statement {
    sid       = "AWSCloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
  statement {
    sid       = "AWSCloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = data.aws_iam_policy_document.trail_bucket.json
}

resource "aws_cloudtrail" "this" {
  #checkov:skip=CKV_AWS_35:SSE-S3 is used; a KMS key is possible future hardening
  #checkov:skip=CKV_AWS_252:No SNS topic needed for this lab
  #checkov:skip=CKV2_AWS_10:CloudWatch Logs integration is out of scope for this lab
  name                          = "${var.name}-trail"
  s3_bucket_name                = aws_s3_bucket.trail.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  depends_on = [aws_s3_bucket_policy.trail]
}

# ---------- Auto-response: contain the agent role when the blocked-actions alarm fires ----------
data "archive_file" "contain" {
  type        = "zip"
  source_file = "${path.module}/contain.py"
  output_path = "${path.module}/contain.zip"
}

data "aws_iam_policy_document" "contain_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "contain" {
  #checkov:skip=CKV_AWS_110:Scoped to a single role ARN; this is the containment action
  #checkov:skip=CKV_AWS_107:Scoped to a single role ARN
  #checkov:skip=CKV_AWS_109:Scoped to a single role ARN
  #checkov:skip=CKV2_AWS_40:Scoped to a single role ARN
  statement {
    actions   = ["iam:PutRolePolicy"]
    resources = [var.agent_role_arn]
  }
  statement {
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name}-contain",
      "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name}-contain:*",
    ]
  }
}

resource "aws_iam_role" "contain" {
  name               = "${var.name}-contain-role"
  assume_role_policy = data.aws_iam_policy_document.contain_assume.json
}

resource "aws_iam_role_policy" "contain" {
  name   = "${var.name}-contain-policy"
  role   = aws_iam_role.contain.id
  policy = data.aws_iam_policy_document.contain.json
}

resource "aws_lambda_function" "contain" {
  #checkov:skip=CKV_AWS_117:Needs to reach the IAM API, so it runs outside the VPC
  #checkov:skip=CKV_AWS_116:Lab function, no dead letter queue needed
  #checkov:skip=CKV_AWS_115:Concurrency limit not needed for a lab
  #checkov:skip=CKV_AWS_173:Environment variables hold a role name only
  #checkov:skip=CKV_AWS_272:Code signing is out of scope for this lab
  #checkov:skip=CKV_AWS_50:X-Ray tracing is out of scope for this lab
  function_name    = "${var.name}-contain"
  role             = aws_iam_role.contain.arn
  runtime          = "python3.12"
  handler          = "contain.handler"
  filename         = data.archive_file.contain.output_path
  source_code_hash = data.archive_file.contain.output_base64sha256
  timeout          = 15

  environment {
    variables = {
      AGENT_ROLE_NAME = var.agent_role_name
    }
  }
}

resource "aws_cloudwatch_event_rule" "alarm" {
  name        = "${var.name}-blocked-actions-alarm"
  description = "Route the blocked-actions alarm to the containment function"
  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = [var.alarm_name]
      state     = { value = ["ALARM"] }
    }
  })
}

resource "aws_cloudwatch_event_target" "contain" {
  rule = aws_cloudwatch_event_rule.alarm.name
  arn  = aws_lambda_function.contain.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.contain.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.alarm.arn
}
