# Random string to ensure global uniqueness for the bucket name
resource "random_id" "bucket_prefix" {
  byte_length = 4
}

# Cloud Storage Bucket
resource "google_storage_bucket" "object_store" {
  name          = "${var.environment}-storage-bucket-${random_id.bucket_prefix.hex}"
  location      = var.region
  storage_class = "STANDARD"

  # Force destroy allows terraform down to remove the bucket even if it contains objects
  force_destroy = true

  # Enforce IAM-only permissions (disables legacy ACLs)
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 90 # Move items or delete after 90 days if desired
    }
    action {
      type = "Delete"
    }
  }
}

# Output the important entrypoints
output "bastion_public_ip" {
  value       = google_compute_instance.linux_vm.network_interface[0].access_config[0].nat_ip
  description = "The public IP address of the Linux VM."
}

output "gcs_bucket_url" {
  value       = google_storage_bucket.object_store.url
  description = "The base URL of the storage bucket."
}

# Authorize public read and list permissions for the GCS Bucket
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.object_store.name
  role   = "roles/storage.objectViewer" # Allows viewing object metadata, listing, and downloading objects
  member = "allUsers"                  # Specifies public internet availability
}