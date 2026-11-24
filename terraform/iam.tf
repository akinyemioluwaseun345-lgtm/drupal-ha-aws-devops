# iam.tf
# Identity for the application servers: an IAM role (trusted by EC2) with the
# Systems Manager managed policy, wrapped in an instance profile so EC2 can use it.

# Trust policy: only the EC2 service may assume this role.
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    sid     = "EC2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${local.name_prefix}-app-ec2-role"
  description        = "Role for Drupal application servers (Systems Manager access)"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name = "${local.name_prefix}-app-ec2-role"
  }
}

# Lets the SSM Agent register the instance and open Session Manager shells
# (replaces SSH).
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Optional, tightly scoped: read ONLY the database secret (see database.tf).
# Useful when Ansible runs on the instances and needs the DB password.
data "aws_iam_policy_document" "read_db_secret" {
  statement {
    sid    = "ReadDatabaseSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [aws_secretsmanager_secret.db.arn]
  }
}

resource "aws_iam_role_policy" "read_db_secret" {
  count = var.enable_instance_db_secret_read ? 1 : 0

  name   = "${local.name_prefix}-read-db-secret"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.read_db_secret.json
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name_prefix}-app-instance-profile"
  role = aws_iam_role.app.name

  tags = {
    Name = "${local.name_prefix}-app-instance-profile"
  }
}