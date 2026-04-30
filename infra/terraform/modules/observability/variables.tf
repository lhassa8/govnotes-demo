variable "name_prefix" {
  description = "Prefix for resource names (e.g. govnotes-fedramp-prod)."
  type        = string
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster whose service health is alarmed on."
  type        = string
}

variable "ecs_service_name" {
  description = "Name of the ECS service backing the app."
  type        = string
}

variable "rds_instance_id" {
  description = "Identifier of the primary RDS instance (analytics DB excluded — its 1-day retention is a deliberate gap)."
  type        = string
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the public ALB for HTTPCode metrics."
  type        = string
}

variable "alarm_actions" {
  description = "SNS topic ARNs (or other action targets) the alarms publish to."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
