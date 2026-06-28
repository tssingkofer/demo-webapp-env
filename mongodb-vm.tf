resource "google_compute_instance" "linux_vm" {
  name         = "${var.environment}-linux-mongodb"
  machine_type = "e2-medium"
  zone         = "${var.region}-c"

  tags = ["mongodb"]

  boot_disk {
    initialize_params {
      # Point to a specific debian image (over 1 year old)
      image = "debian-12-bookworm-v20250513"
      size  = 30 
    }
  }

  network_interface {
    # subnetwork = "default"

    subnetwork = google_compute_subnetwork.public_subnet.id

    access_config {
      network_tier = "STANDARD"
    }
  }

  # Startup script installs MongoDB 6.0, provisions an admin, and enforces authorization
  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -e 

    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl gnupg gnupg2

    wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc |  gpg --dearmor | sudo tee /usr/share/keyrings/mongodb.gpg > /dev/null 
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list
    apt-get update
    apt-get install -y mongodb-org

    systemctl daemon-reload
    systemctl start mongod
    systemctl enable mongod

    # Wait for MongoDB to wake up and start accepting connections
    until mongosh --eval "print(\"waited for connection\")" &>/dev/null; do
        sleep 2
    done

    # Provision the admin account
    mongosh admin --eval '
      db.createUser({
        user: "admin",
        pwd: "${var.mongodb_password}",
        roles: [ { role: "root", db: "admin" } ]
      })
    '

    # Enable Access Control 
cat << 'EOF' > /etc/mongod.conf
storage:
  dbPath: /var/lib/mongodb

systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log

net:
  port: 27017
  bindIp: 0.0.0.0

security:
  authorization: enabled
EOF

    systemctl restart mongod

    cat << 'EOF' > /usr/local/bin/mongo_backup_to_gcs.sh
    #!/bin/bash
    BACKUP_DIR="/tmp/mongobackups"
    BUCKET_NAME="${google_storage_bucket.object_store.name}"
    TIMESTAMP=$(date +%F_%H%M%S)
    BACKUP_NAME="mongo_backup_$TIMESTAMP.gz"
    BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

    mkdir -p $BACKUP_DIR

    echo "[$TIMESTAMP] Starting authenticated MongoDB dump..."
    # Explicitly using the admin credentials to create the dump file
    mongodump --username "admin" --password "${var.mongodb_password}" --authenticationDatabase "admin" --archive=$BACKUP_PATH --gzip

    echo "[$TIMESTAMP] Fetching GCE access token..."
    ACCESS_TOKEN=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | grep -o '"access_token":"[^"]*' | grep -o '[^"]*$')

    echo "[$TIMESTAMP] Uploading backup to GCS bucket: $BUCKET_NAME..."
    curl -X POST \
      --data-binary @$BACKUP_PATH \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/gzip" \
      "https://storage.googleapis.com/upload/storage/v1/b/$BUCKET_NAME/o?uploadType=media&name=$BACKUP_NAME"

    rm -f $BACKUP_PATH
    echo "[$TIMESTAMP] Backup workflow completed successfully."
EOF

    chmod +x /usr/local/bin/mongo_backup_to_gcs.sh
    echo "*/30 * * * * root /usr/local/bin/mongo_backup_to_gcs.sh >> /var/log/mongo_gcs_backup.log 2>&1" > /etc/cron.d/mongo-gcs-backup
  EOT

  service_account {
    email  = google_service_account.vm_sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}

resource "google_service_account" "vm_sa" {
  account_id   = "${var.environment}-vm-sa"
  display_name = "Linux VM Service Account"
}

# Grant the VM service account permission to write to your specific GCS bucket
resource "google_storage_bucket_iam_member" "vm_storage_writer" {
  bucket = google_storage_bucket.object_store.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.vm_sa.email}"
}

#Grant the VM service account Compute Admin rights at the project level
resource "google_project_iam_member" "vm_compute_admin" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}

#Allow the VM service account to assign service accounts to the new VMs it creates
resource "google_project_iam_member" "vm_sa_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}