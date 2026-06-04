output "daily_bucket_url" {
  value = "gs://${google_storage_bucket.daily.name}"
}

output "weekly_bucket_url" {
  value = "gs://${google_storage_bucket.weekly.name}"
}

output "monthly_bucket_url" {
  value = "gs://${google_storage_bucket.monthly.name}"
}

output "backup_service_account_email" {
  value = google_service_account.backup_uploader.email
}
