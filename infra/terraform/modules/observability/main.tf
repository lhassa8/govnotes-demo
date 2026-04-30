# Observability module — CloudWatch alarms on the critical
# infrastructure metrics the SOC needs to see paged on. Wraps the
# detection of failing-app, RDS-CPU-saturated, and ALB-5xx-spike into
# one composable unit so future workloads get the same alarm coverage
# without copy-pasting the resource declarations.
#
# This module is a deliberate exercise of module composition for
# Efterlev's plan-JSON scan mode: HCL-mode detectors don't follow into
# module bodies, so resources declared here surface only when the user
# runs `efterlev scan --plan plan.json`. Compare HCL-mode evidence
# count to plan-mode evidence count to see the lift.

resource "aws_cloudwatch_metric_alarm" "ecs_service_unhealthy" {
  alarm_name          = "${var.name_prefix}-ecs-service-unhealthy"
  alarm_description   = "Fewer than the desired count of ECS tasks are RUNNING in the app service. Page the on-call."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = 2
  treat_missing_data  = "breaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu_saturated" {
  alarm_name          = "${var.name_prefix}-rds-cpu-saturated"
  alarm_description   = "Primary RDS instance CPU sustained above 85% for 10 minutes. Investigate query plan / scale up."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 120
  statistic           = "Average"
  threshold           = 85
  treat_missing_data  = "missing"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx_spike" {
  alarm_name          = "${var.name_prefix}-alb-5xx-spike"
  alarm_description   = "ALB returning 5xx at >0.5% of requests over 5 minutes. App or downstream is degraded."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  tags = var.tags
}
