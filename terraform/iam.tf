# =====================================================================
# IAM
#
# Three roles, each with a different owner:
#
#   execution role  assumed by the ECS agent, before the container runs
#   task role       assumed by the application process itself
#   deploy role     assumed by GitHub Actions through OIDC
#
# The application never calls an AWS API, so its task role carries no
# data permissions at all.
# =====================================================================

# ---------------------------------------------------------------------
# ECS task execution role — pulls the image, resolves the secret,
# writes logs. Used by the ECS agent, not by application code.
# ---------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${var.name_prefix}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Written by hand rather than attaching a broad managed policy: the
# resource is one secret ARN, not a wildcard. If this role leaked it
# could not read any other secret in the account.
data "aws_iam_policy_document" "read_db_secret" {
  statement {
    sid       = "ReadDatabaseUrlSecretOnly"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db_url.arn]
  }
}

resource "aws_iam_role_policy" "ecs_execution_secret" {
  name   = "read-db-url-secret"
  role   = aws_iam_role.ecs_execution.id
  policy = data.aws_iam_policy_document.read_db_secret.json
}

# ---------------------------------------------------------------------
# ECS task role — assumed by the container process.
#
# The application makes no AWS API calls, so this role exists only to
# carry the three actions ECS Exec needs. ssmmessages does not support
# resource level permissions; the wildcard is a service limitation, and
# these actions open an interactive channel rather than touch data.
# ---------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_exec" {
  statement {
    sid = "EcsExecSessionChannel"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "ecs_task" {
  name               = "${var.name_prefix}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy" "ecs_task_exec" {
  name   = "ecs-exec"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_exec.json
}

# ---------------------------------------------------------------------
# GitHub Actions OIDC — short lived credentials, no stored access keys
# ---------------------------------------------------------------------
# Note: an account can only hold one provider for this URL. If the
# account already has one, import it instead of creating a second.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # No thumbprint: AWS verifies GitHub's certificate against its root CA.
}

# The subject condition pins this role to one branch of one repository.
# A pull request from a fork, or a push to any other branch, cannot
# obtain these credentials.
data "aws_iam_policy_document" "github_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    /* condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}@*:ref:refs/heads/main"]
    } */

    # GitHub appends an immutable numeric id to both the owner and the
    # repository name in the subject claim — for example
    #   repo:owner@73279182/repo@1356771410:ref:refs/heads/main
    # so that renaming a repository cannot inherit the old name's trust.
    # The wildcards cover only those ids. The branch is still matched
    # exactly, so a fork or any other branch cannot assume this role.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}*/${var.github_repo_name}*:ref:refs/heads/${var.github_branch}"]
    }

  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.name_prefix}-github-deploy-role"
  assume_role_policy = data.aws_iam_policy_document.github_assume.json
}

# The pipeline pushes an image and points the service at a new task
# definition revision. It cannot reach the VPC, the database or any
# other service. If the pipeline is compromised, the blast radius is
# this one ECS service.
data "aws_iam_policy_document" "github_deploy" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this action has no resource scope
  }

  statement {
    sid = "PushToThisRepositoryOnly"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    sid = "ReadAndRegisterTaskDefinitions"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
    ]
    resources = ["*"] # neither action supports resource level permissions
  }

  statement {
    sid = "UpdateThisServiceOnly"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = [aws_ecs_service.app.id]
  }

  # RegisterTaskDefinition embeds these roles, so the caller must be
  # allowed to pass them. The condition limits passing to ECS.
  statement {
    sid     = "PassTaskRolesToEcsOnly"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.ecs_execution.arn,
      aws_iam_role.ecs_task.arn,
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "deploy-wallet-service"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}
