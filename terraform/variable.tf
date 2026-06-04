variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "bucket_location" {
  type        = string
  description = "ASIA-NORTHEAST1"
}

variable "bucket_name_daily" {
  type = string
}

variable "bucket_name_weekly" {
  type = string
}

variable "bucket_name_monthly" {
  type = string
}

variable "allowed_upload_ips" {
  type = list(string)
}
