output "alarm_names" {
  description = "Names of every CloudWatch alarm declared by this module."
  value = [
    aws_cloudwatch_metric_alarm.ecs_service_unhealthy.alarm_name,
    aws_cloudwatch_metric_alarm.rds_cpu_saturated.alarm_name,
    aws_cloudwatch_metric_alarm.alb_5xx_spike.alarm_name,
  ]
}
