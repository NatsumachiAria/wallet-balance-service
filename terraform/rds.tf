# =====================================================================
# RDS — managed PostgreSQL
#
# Single-AZ is a deliberate reduction in availability tier, not a change
# of engine. The instance keeps automated backups and point in time
# recovery, so a failure costs visibility rather than data. The
# reasoning, and what would change for real financial data, is in the
# README.
# =====================================================================

resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = { Name = "${var.name_prefix}-db-subnet-group" }
}

resource "aws_db_instance" "main" {
  identifier     = "${var.name_prefix}-postgres"
  engine         = "postgres"
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class

  allocated_storage = var.rds_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.rds_db_name
  username = var.rds_username

  # RDS generates the master password, stores it in Secrets Manager and
  # rotates it. No password is ever passed through Terraform, so none
  # appears in state, in a plan output, or in the repository.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]

  # Private subnets have no route to an internet gateway. This flag adds
  # a second, explicit barrier at the instance level.
  publicly_accessible = false

  multi_az                = false
  backup_retention_period = var.rds_backup_retention_days

  auto_minor_version_upgrade = true
  apply_immediately          = true

  # Exercise environment only. Both would be inverted for production.
  skip_final_snapshot = true
  deletion_protection = false

  tags = { Name = "${var.name_prefix}-postgres" }
}
