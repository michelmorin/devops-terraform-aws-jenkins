terraform {
  required_version = ">= 0.12"

  #backend "remote" {
  #  organization = "MorinLearning"

  #  workspaces {
  #    name = "getting-started"
  #  }
  #}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  region = "ca-central-1"
  alias  = "canada"
}

