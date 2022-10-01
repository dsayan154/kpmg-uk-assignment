terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "4.33.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
  profile = "sayan-local-admin"
}

