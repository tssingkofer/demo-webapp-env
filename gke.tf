# GKE Cluster Control Plane
resource "google_container_cluster" "private_cluster" {
  name     = "${var.environment}-gke-cluster"
  location = var.region

  deletion_protection = false

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  # Recommended: Start with a decoupled architecture by deleting the default node pool immediately
  remove_default_node_pool = true
  initial_node_count       = 1

  # Network Routing Configuration (Alias IP)
  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }

  # Private Cluster Configuration
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false # Set to true to completely block internet access to the master API
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Master Authorized Networks (Restrict who can run kubectl commands)
  # Modify these blocks to match your internal network or bastion host CIDRs
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "Temporary-Public-Access"
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

# Custom Managed Node Pool
resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.environment}-primary-node-pool"
  location   = var.region
  cluster    = google_container_cluster.private_cluster.name
  node_count = 2

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    preemptible  = false
    machine_type = "e2-standard-2"

    # Use a dedicated IAM Service Account with minimal permissions instead of Compute Engine default
    service_account = google_service_account.gke_sa.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = {
      env = var.environment
    }

    # Secure the metadata server endpoints
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}

# Minimal IAM Service Account for GKE Nodes
resource "google_service_account" "gke_sa" {
  account_id   = "${var.environment}-gke-node-sa"
  display_name = "GKE Node Pool Service Account"
}