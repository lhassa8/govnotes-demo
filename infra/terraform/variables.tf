variable "environment" {
  description = "Environment name. Drives resource naming and tagging."
  type        = string
  default     = "fedramp-prod"
}

variable "region" {
  description = "AWS region. The FedRAMP boundary lives in us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the FedRAMP boundary VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "availability_zones" {
  description = "AZs to spread subnets across."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "app_domain" {
  description = "Customer-facing domain for the app tier."
  type        = string
  default     = "app.gov.govnotes.com"
}

variable "app_image" {
  description = "ECR image URI for the Govnotes app service."
  type        = string
  default     = "000000000000.dkr.ecr.us-east-1.amazonaws.com/govnotes/app:latest"
}

variable "db_instance_class" {
  description = "RDS instance class for the primary app database."
  type        = string
  default     = "db.r6g.large"
}

variable "db_allocated_storage" {
  description = "Allocated storage for the primary app database, in GB."
  type        = number
  default     = 200
}

variable "db_username" {
  description = "Master username for the primary app database."
  type        = string
  default     = "govnotes_app"
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for the customer-facing ALB listener."
  type        = string
  default     = "arn:aws:acm:us-east-1:000000000000:certificate/REPLACE-ME"
}

variable "tags" {
  description = "Default tags applied via the provider default_tags block."
  type        = map(string)
  default = {
    Product     = "govnotes"
    Environment = "fedramp-prod"
    Boundary    = "fedramp-moderate"
    Owner       = "platform-team"
    ManagedBy   = "terraform"
  }
}
