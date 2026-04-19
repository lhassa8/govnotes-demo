terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {
    bucket         = "govnotes-fedramp-tfstate"
    key            = "fedramp-prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "govnotes-fedramp-tfstate-locks"
    encrypt        = true
  }
}
