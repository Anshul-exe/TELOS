terraform {
  required_version = ">= 1.5.0"

  # Local backend on purpose: this config bootstraps the S3 bucket + DynamoDB
  # table that every OTHER config will use as its remote backend. It cannot
  # store its own state remotely in a backend that does not exist yet, so its
  # state lives on disk here (terraform.tfstate) and is committed-ignored.
  backend "local" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region
}
