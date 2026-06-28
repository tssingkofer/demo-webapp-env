terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  backend "gcs" {
    bucket = "global-tfstate-bucket"
    prefix = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  type        = string
  default     = "clgcporg10-165"
  description = "The GCP Project ID"
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "The primary region for resources"
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Environment tag (e.g., dev, prod)"
}

variable "mongodb_password" {
  type        = string
  description = "Password to the MongoDB admin account"
}