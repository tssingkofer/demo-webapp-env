# Custom VPC
resource "google_compute_network" "vpc" {
  name                    = "${var.environment}-vpc"
  auto_create_subnetworks = false
}

# Private Subnet with Secondary Ranges for GKE
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.environment}-gke-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.0.0.0/20" # Node IP range

  # Secondary ranges for Alias IPs
  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.4.0.0/14"
  }

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "10.8.0.0/20"
  }

  private_ip_google_access = true
}

# Cloud Router (Required for Cloud NAT)
resource "google_compute_router" "router" {
  name    = "${var.environment}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

# Cloud NAT (Allows private nodes to reach the internet)
resource "google_compute_router_nat" "nat" {
  name                               = "${var.environment}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

# Public Subnet for the Linux VM / Bastion Host
resource "google_compute_subnetwork" "public_subnet" {
  name          = "${var.environment}-public-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.10.0.0/24"
}

# Firewall rule to allow SSH access to the public VM
resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.environment}-allow-ssh"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # For security, replace "0.0.0.0/0" with your specific local public IP address
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["mongodb"]
}

# Allow GKE Pods to connect to MongoDB on port 27017
resource "google_compute_firewall" "allow_gke_to_mongodb" {
  name    = "${var.environment}-allow-gke-to-mongodb"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["27017"]
  }

  # Source range matches the "gke-pods" secondary IP allocation block
  source_ranges = [
    "10.4.0.0/14",
    "10.0.0.0/20"
  ]

  # Targets the MongoDB VM via its network tag
  target_tags = ["mongodb"]
}