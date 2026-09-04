# =====================================================================
# SECRETS MANAGER — application database connection string
#
# Two secrets exist in this system:
#
#   1. The RDS master user secret, created and owned by RDS itself
#      through manage_master_user_password. Terraform never sees the
#      password, so it never enters state, a plan output or CI logs.
#
#   2. This secret, which holds the full DATABASE_URL the application
#      reads. Only the container is declared here — no
#      aws_secretsmanager_secret_version resource — because writing the
#      value through Terraform would pull the password into state and
#      undo the point of (1).
#
# Terraform owns the address, an operator writes the value once during
# bootstrap. The command is documented in the README.
# =====================================================================

resource "aws_secretsmanager_secret" "db_url" {
  name        = "${var.name_prefix}/database-url"
  description = "Full PostgreSQL connection string consumed by the app as DATABASE_URL"

  # Exercise environment: makes the name reusable immediately after a
  # destroy instead of being held in a 30 day recovery window.
  recovery_window_in_days = 0

  tags = { Name = "${var.name_prefix}-database-url" }
}
