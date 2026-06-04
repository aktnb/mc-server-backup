resource "google_service_account" "backup_uploader" {
  account_id   = "minecraft-backup-uploader"
  display_name = "Minecraft Backup Uploader"
}

resource "google_storage_bucket_iam_member" "daily_uploader" {
  bucket = google_storage_bucket.daily.name

  role = "roles/storage.objectCreator"

  member = "serviceAccount:${google_service_account.backup_uploader.email}"
}

resource "google_storage_bucket_iam_member" "weekly_uploader" {
  bucket = google_storage_bucket.weekly.name

  role = "roles/storage.objectCreator"

  member = "serviceAccount:${google_service_account.backup_uploader.email}"
}

resource "google_storage_bucket_iam_member" "monthly_uploader" {
  bucket = google_storage_bucket.monthly.name

  role = "roles/storage.objectCreator"

  member = "serviceAccount:${google_service_account.backup_uploader.email}"
}
