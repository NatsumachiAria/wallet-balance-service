# =====================================================================
# ECS FARGATE — cluster, task definition, service
#
# Fargate rather than EKS: this is one service with no requirement that
# points at Kubernetes. Fargate rather than EC2: nothing here justifies
# owning host patching for a single container.
#
# Terraform creates revision 1 of the task definition. From then on the
# pipeline owns the image tag and nothing else, which is why
# task_definition is in ignore_changes below.
# =====================================================================

resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"

  tags = { Name = "${var.name_prefix}-cluster" }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.name_prefix}-balance-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory

  # Two roles, two owners. The execution role belongs to the ECS agent
  # and is used before the container starts. The task role belongs to
  # the application process.
  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = var.ecs_container_name
      image     = "${aws_ecr_repository.app.repository_url}:${var.ecr_image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.ecs_container_port
          protocol      = "tcp"
        }
      ]

      # Plain values. Anything placed here is visible to anyone who can
      # read the task definition.
      environment = [
        {
          name  = "PORT"
          value = tostring(var.ecs_container_port)
        }
      ]

      # An ARN, not a value. The ECS agent exchanges it for the secret
      # using the execution role at task startup, before the process
      # begins, so the application only ever reads process.env and never
      # calls an AWS API.
      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = aws_secretsmanager_secret.db_url.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = { Name = "${var.name_prefix}-balance-service" }
}

resource "aws_ecs_service" "app" {
  name            = "${var.name_prefix}-balance-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  launch_type     = "FARGATE"

  # Two tasks so a rolling deployment always leaves one serving. This is
  # for deployment continuity, not for load: the workload is a single
  # key lookup.
  desired_count = var.ecs_desired_count

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # Fargate cold start plus the TLS handshake and authentication against
  # RDS take time. Without this grace period the first health check can
  # kill a task that was still coming up.
  health_check_grace_period_seconds = 60

  # Opens an interactive shell into a running task. This is the only
  # administrative access path; there is no bastion host. It is also how
  # the database schema was loaded during bootstrap.
  enable_execute_command = true

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.ecs_container_name
    container_port   = var.ecs_container_port
  }

  # The service cannot register targets until the listener exists.
  depends_on = [aws_lb_listener.http]

  # The pipeline registers new task definition revisions. Without this,
  # the next terraform apply would drag the service back to revision 1
  # and roll the running image backwards.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  tags = { Name = "${var.name_prefix}-balance-service" }
}
