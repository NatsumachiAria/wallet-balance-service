# =====================================================================
# APPLICATION LOAD BALANCER — internal
#
# The service exposes an unauthenticated /balance endpoint, so the load
# balancer is not internet facing. It is reachable only from inside the
# VPC, and is exercised from a task shell opened through ECS Exec.
# =====================================================================

resource "aws_lb" "main" {
  name               = "${var.name_prefix}-alb"
  internal           = true
  load_balancer_type = "application"
  subnets            = aws_subnet.private[*].id
  security_groups    = [aws_security_group.alb.id]

  tags = { Name = "${var.name_prefix}-alb" }
}

resource "aws_lb_target_group" "app" {
  name        = "${var.name_prefix}-tg"
  port        = var.ecs_container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Fargate tasks register by ENI address, not instance id

  # The check points at /health, which answers without touching the
  # database. An ALB health check failure on ECS does not only stop
  # routing, it makes ECS replace the task, and replacing a task does
  # not repair a database outage. /ready remains available for operators
  # and for a synthetic check. See the README for the full trade-off.
  health_check {
    path                = var.alb_health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3 # tolerate a single network blip
  }

  # Let in flight requests finish before a task is cut during a rolling
  # deployment.
  deregistration_delay = 30

  tags = { Name = "${var.name_prefix}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
