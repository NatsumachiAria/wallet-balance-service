# =====================================================================
# GLOBAL
# =====================================================================

variable "region" {
  description = "AWS region for every resource in this configuration"
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to the name of every resource"
  type        = string
}

# =====================================================================
# NETWORKING — networking.tf
# VPC, subnets, internet gateway, NAT gateway, route tables, S3 endpoint
# =====================================================================

variable "vpc_cidr" {
  description = "CIDR block of the VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones. Order must match the subnet CIDR lists below."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnets. These host the NAT gateway and nothing else."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnets. ALB, ECS tasks and RDS all live here."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least two private subnets in different AZs are required: both the ALB and the RDS subnet group need two availability zones."
  }
}

# =====================================================================
# ECR — ecr.tf
# =====================================================================

variable "ecr_image_tag" {
  description = "Image tag referenced by task definition revision 1 during bootstrap. The pipeline owns the tag from then on."
  type        = string
}

# =====================================================================
# ECS / FARGATE — ecs.tf
# =====================================================================

variable "ecs_container_name" {
  description = "Container name. Must match container-name in the deploy workflow."
  type        = string
}

variable "ecs_container_port" {
  description = "Port the application listens on"
  type        = number
}

variable "ecs_task_cpu" {
  description = "Fargate CPU units. 256 equals 0.25 vCPU."
  type        = number
}

variable "ecs_task_memory" {
  description = "Task memory in MiB. Valid values depend on the CPU size chosen."
  type        = number
}

variable "ecs_desired_count" {
  description = "Number of tasks. Two so a rolling deployment always leaves one serving, not for load."
  type        = number
}

# =====================================================================
# RDS — rds.tf
# =====================================================================

variable "rds_engine_version" {
  description = "PostgreSQL major version. RDS selects the latest supported minor."
  type        = string
}

variable "rds_instance_class" {
  type = string
}

variable "rds_allocated_storage" {
  description = "Storage in GB"
  type        = number
}

variable "rds_db_name" {
  description = "Initial database name"
  type        = string
}

variable "rds_username" {
  description = "Master username. There is no password variable: RDS generates and stores it in Secrets Manager."
  type        = string
}

variable "rds_backup_retention_days" {
  description = "Automated backup retention. Any value above zero also enables point in time recovery."
  type        = number
}

# =====================================================================
# ALB — alb.tf
# =====================================================================

variable "alb_health_check_path" {
  description = "Target group health check path. /health rather than /ready; see the README for the trade-off."
  type        = string
}

# =====================================================================
# MONITORING — monitoring.tf
# =====================================================================

variable "alarm_5xx_threshold" {
  description = "5XX responses per evaluation period that count as abnormal"
  type        = number
}

# =====================================================================
# MAINTENANCE HOST — bastion.tf
# =====================================================================

variable "bastion_instance_type" {
  description = "Maintenance host size. It runs psql and nothing else."
  type        = string
}

# =====================================================================
# CI/CD IAM — iam.tf
# =====================================================================

variable "github_repo" {
  description = "owner/repo. Pins the OIDC trust policy to this repository."
  type        = string
}
