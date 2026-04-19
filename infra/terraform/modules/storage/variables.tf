variable "name_prefix" {
  description = "Resource name prefix, typically \"govnotes-<environment>\"."
  type        = string
}

variable "suffix" {
  description = "Random suffix appended to bucket names for global uniqueness."
  type        = string
}

variable "buckets" {
  description = <<-EOT
    Map of bucket configurations. The key becomes part of the bucket
    name (e.g. "artifacts" -> govnotes-fedramp-prod-artifacts-<suffix>).

    Defaults are intentionally minimal; each caller is expected to opt
    into encryption and versioning explicitly per bucket.
  EOT
  type = map(object({
    purpose     = string
    kms_key_arn = optional(string)
    sse_s3      = optional(bool, false)
    versioning  = optional(bool, false)
  }))
}

variable "tags" {
  description = "Extra tags merged onto every resource in the module."
  type        = map(string)
  default     = {}
}
