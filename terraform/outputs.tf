# =====================================================================
# OUTPUTS — values needed for bootstrap, for the pipeline, and for
# manual verification
# =====================================================================

# ---------- Bootstrap ----------
output "ecr_repository_url" {
  description = "Push the initial image here before applying the ECS service"
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_login_command" {
  value = "aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}

output "rds_master_secret_arn" {
  description = "Secret created by RDS. Read it once to compose DATABASE_URL."
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}

output "db_url_secret_name" {
  description = "Write the composed connection string into this secret"
  value       = aws_secretsmanager_secret.db_url.name
}

output "rds_endpoint" {
  value = aws_db_instance.main.endpoint
}

# ---------- Pipeline configuration ----------
output "github_deploy_role_arn" {
  description = "Set as the role-to-assume in the GitHub Actions workflow"
  value       = aws_iam_role.github_deploy.arn
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  value = aws_ecs_service.app.name
}

output "ecs_task_definition_family" {
  value = aws_ecs_task_definition.app.family
}

# ---------- Verification ----------
output "alb_dns_name" {
  description = "Internal only. Reachable from a task shell opened with ECS Exec."
  value       = aws_lb.main.dns_name
}

output "bastion_instance_id" {
  description = "Target for aws ssm start-session"
  value       = aws_instance.bastion.id
}
