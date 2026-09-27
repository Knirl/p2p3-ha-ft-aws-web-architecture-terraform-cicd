terraform {
  # >= 1.10 is required for the S3 backend's native state locking
  # (use_lockfile below) — this is the modern replacement for the old
  # "S3 bucket + separate DynamoDB table for locking" pattern. One less
  # resource to provision and pay for compared to the DynamoDB approach.
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.65" #latest v6.x major release line
    }

    # a utility plugin to generate random values (like strings, passwords, numbers, or IDs) during the Terraform deployment.
    # Pulled in transitively by the database module (random_password) and the storage module (random_id for the bucket name suffix).
    # Upgraded to catch the latest v3.x enhancements (like ephemeral resource types)
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # IMPORTANT — this block cannot use variables or locals. Terraform reads backend configuration before it evaluates any variable, so everything here has to be a literal value. 
  # Bucker below create

  backend "s3" {
    bucket       = "p2p3-tfstate-amboy"
    key          = "p2p3/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}



provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags # Automatically applies a predefined set of key-value pairs (stored in a local variable named common_tags, such as Project = "MyProject" or Environment = "Production") to every AWS resource created in this configuration
  }
}
