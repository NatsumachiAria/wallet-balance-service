# =====================================================================
# SECURITY GROUPS
#
# Kept in one file on purpose: a rule such as "5432 from the app SG" is
# an edge between two services, not a property of either one, so the
# whole network policy reads top to bottom in a single place.
#
# Rules are separate resources rather than inline blocks so that a
# change to one rule does not force the security group to be replaced.
#
#   alb SG  <- 80    from app SG, bastion SG
#   app SG  <- 3000  from alb SG
#   db  SG  <- 5432  from app SG, bastion SG
#
# Every rule references another security group instead of a CIDR range.
# A CIDR grants access to anything that happens to hold an address in
# that range, including resources created later. A group reference
# grants access by identity.
# =====================================================================

# ---------- Application Load Balancer ----------
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Internal ALB"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.name_prefix}-alb-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_app" {
  description                  = "HTTP from ECS tasks (the only client of the internal ALB)"
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  description                  = "Forward and health check traffic to ECS tasks"
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = var.ecs_container_port
  to_port                      = var.ecs_container_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_bastion" {
  description                  = "HTTP from the maintenance host, for verifying the request path"
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.bastion.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

# ---------- ECS tasks ----------
resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-app-sg"
  description = "Fargate tasks running wallet-balance-service"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.name_prefix}-app-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  description                  = "Application port from the ALB only"
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.ecs_container_port
  to_port                      = var.ecs_container_port
  ip_protocol                  = "tcp"
}

# Egress is left open. The task pulls images from ECR, resolves a secret
# from Secrets Manager, ships logs to CloudWatch and reaches RDS. Without
# a full set of interface VPC endpoints those destinations are public AWS
# endpoints behind NAT, so pinning them to ports would be guesswork.
# Narrowing this is listed as a TODO in the README alongside the VPC
# endpoint work it depends on.
resource "aws_vpc_security_group_egress_rule" "app_all" {
  description       = "Outbound to AWS service endpoints and RDS"
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------- RDS ----------
# No egress rules are declared, which means the database has no outbound
# access at all. RDS does not need any: backups and managed password
# rotation are handled by AWS outside this network interface.
resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db-sg"
  description = "RDS PostgreSQL"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.name_prefix}-db-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  description                  = "PostgreSQL from ECS tasks only"
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# ---------- Maintenance host ----------
# No ingress rules at all. The SSM agent opens an outbound channel, so
# nothing needs to connect inward and port 22 is never exposed.
resource "aws_security_group" "bastion" {
  name        = "${var.name_prefix}-bastion-sg"
  description = "Maintenance host reached through SSM Session Manager"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.name_prefix}-bastion-sg" }
}

resource "aws_vpc_security_group_egress_rule" "bastion_all" {
  description       = "Outbound to Systems Manager, package repositories, RDS and the ALB"
  security_group_id = aws_security_group.bastion.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "db_from_bastion" {
  description                  = "PostgreSQL from the maintenance host, for schema work"
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.bastion.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}
