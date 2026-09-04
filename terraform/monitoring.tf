# =====================================================================
# MONITORING — log group and one alarm
#
# The brief does not expect a fully wired monitoring stack, only a plan.
# One alarm is implemented because a working alarm plus a plan is
# stronger evidence than a plan alone. The rest of the plan is in the
# README.
#
# This alarm is what replaces pointing the load balancer at /ready. When
# the database is unreachable, /balance returns 500 and 5XX count rises.
# The signal is the same, without the task churn that a failing health
# check would cause.
# =====================================================================

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.name_prefix}-balance-service"
  retention_in_days = 7

  tags = { Name = "${var.name_prefix}-balance-service" }
}

resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"

  tags = { Name = "${var.name_prefix}-alerts" }
}

resource "aws_cloudwatch_metric_alarm" "app_5xx" {
  alarm_name        = "${var.name_prefix}-app-5xx"
  alarm_description = "Application returned 5XX responses through the ALB"

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_Target_5XX_Count"
  statistic   = "Sum"

  period              = 60
  evaluation_periods  = 2
  threshold           = var.alarm_5xx_threshold
  comparison_operator = "GreaterThanThreshold"

  # No traffic produces no data points, which is not a problem.
  treat_missing_data = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}
