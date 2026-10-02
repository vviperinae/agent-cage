variable "name" {
  type    = string
  default = "agent-cage"
}

data "aws_caller_identity" "current" {}

# Bucket the agent is allowed to read (its "inbox" of documents)
resource "aws_s3_bucket" "inbox" {
  #checkov:skip=CKV2_AWS_62:No event-driven processing in this lab
  #checkov:skip=CKV_AWS_18:Access logging needs a separate log bucket; CloudTrail covers access auditing
  #checkov:skip=CKV_AWS_144:Cross-region replication is unnecessary for a disposable lab
  #checkov:skip=CKV_AWS_145:Default SSE-S3 encryption is enabled; a KMS key adds cost and complexity for a throwaway lab
  bucket        = "${var.name}-inbox-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

# Bucket holding the "secret" the injected prompt will try to steal
resource "aws_s3_bucket" "secret" {
  #checkov:skip=CKV2_AWS_62:No event-driven processing in this lab
  #checkov:skip=CKV_AWS_18:Access logging needs a separate log bucket; CloudTrail covers access auditing
  #checkov:skip=CKV_AWS_144:Cross-region replication is unnecessary for a disposable lab
  #checkov:skip=CKV_AWS_145:Default SSE-S3 encryption is enabled; a KMS key adds cost and complexity for a throwaway lab
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
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.inbox.arn}/*"]
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.inbox.arn]
  }
  statement {
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name}-*",
      "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name}-*:*",
    ]
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
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name}-*",
      "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name}-*:*",
    ]
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

resource "aws_s3_bucket_versioning" "inbox" {
  bucket = aws_s3_bucket.inbox.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_versioning" "secret" {
  bucket = aws_s3_bucket.secret.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_lifecycle_configuration" "inbox" {
  bucket = aws_s3_bucket.inbox.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "secret" {
  bucket = aws_s3_bucket.secret.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_iam_policy" "boundary" {
  name   = "${var.name}-boundary"
  policy = data.aws_iam_policy_document.boundary.json
}
