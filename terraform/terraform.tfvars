# =====================================================================
# Committed deliberately. This file contains no credentials: RDS
# generates the master password and stores it in Secrets Manager, so
# Terraform never handles it.
# Sections match variables.tf in the same order.
# =====================================================================

# =====================================================================
# GLOBAL
# =====================================================================
region      = "ap-southeast-1"
name_prefix = "wallet"

# =====================================================================
# NETWORKING — networking.tf
# =====================================================================
vpc_cidr             = "10.0.0.0/16"
azs                  = ["ap-southeast-1a", "ap-southeast-1b"]
public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

# =====================================================================
# ECR — ecr.tf
# =====================================================================
ecr_image_tag = "bootstrap"

# =====================================================================
# ECS / FARGATE — ecs.tf
# =====================================================================
ecs_container_name = "app"
ecs_container_port = 3000
ecs_task_cpu       = 256
ecs_task_memory    = 512
ecs_desired_count  = 2

# =====================================================================
# RDS — rds.tf
# =====================================================================
rds_engine_version        = "18"
rds_instance_class        = "db.t4g.micro"
rds_allocated_storage     = 20
rds_db_name               = "wallet"
rds_username              = "wallet"
rds_backup_retention_days = 7

# =====================================================================
# ALB — alb.tf
# =====================================================================
alb_health_check_path = "/health"

# =====================================================================
# MONITORING — monitoring.tf
# =====================================================================
alarm_5xx_threshold = 5

# =====================================================================
# MAINTENANCE HOST — bastion.tf
# =====================================================================
bastion_instance_type = "t3.micro"

# =====================================================================
# CI/CD IAM — iam.tf
# =====================================================================
github_repo = "NatsumachiAria/wallet-balance-service"
