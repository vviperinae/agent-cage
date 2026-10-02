variable "name" {
  type    = string
  default = "agent-cage"
}

data "aws_caller_identity" "current" {}

# Bucket the agent is allowed to read (its "inbox" of documents)
resource "aws_s3_bucket" "inbox" {
  bucket        = "${var.name}-inbox-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

# Bucket holding the "secret" the injected prompt will try to steal
resource "aws_s3_bucket" "secret" {
  bucket        = "${var.name}-secret-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "inbox" {
  bucket                  = aws_s3_bucket.inbox.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "secret" {
  bucket                  = aws_s3_bucket.secret.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Role the agent assumes (Lambda for now)
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Permissions boundary: the hard ceiling, even if someone later attaches more
data "aws_iam_policy_document" "boundary" {
  statement {
    actions   = ["s3:GetObject", "s3:ListBucket", "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "boundary" {
  name   = "${var.name}-boundary"
  policy = data.aws_iam_policy_document.boundary.json
}

resource "aws_iam_role" "agent" {
  name                 = "${var.name}-role"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  permissions_boundary = aws_iam_policy.boundary.arn
}

# Actual permissions: read the inbox bucket only
data "aws_iam_policy_document" "agent" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.inbox.arn}/*"]
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.inbox.arn]
  }
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role_policy" "agent" {
  name   = "${var.name}-policy"
  role   = aws_iam_role.agent.id
  policy = data.aws_iam_policy_document.agent.json
}

output "agent_role_arn" { value = aws_iam_role.agent.arn }
output "inbox_bucket" { value = aws_s3_bucket.inbox.id }
output "secret_bucket" { value = aws_s3_bucket.secret.id }
