# Terraform configuration

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

data "terraform_remote_state" "projectreclass-terraform-california" {
  backend = "s3" 
  config = {
    bucket = "projectreclass-terraform-california"
    key    = "terraform.tfstate"
    region = "us-west-1"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

provider "aws" {
  region = "us-west-1"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.21.0"

  name = var.vpc_name
  cidr = var.vpc_cidr
  
  azs             = data.aws_availability_zones.available.names 
  private_subnets = var.vpc_private_subnets
  public_subnets  = var.vpc_public_subnets

  enable_nat_gateway = var.vpc_enable_nat_gateway

  tags = var.vpc_tags
}

terraform {
  backend "s3" {
    bucket = "projectreclass-terraform-california"
    key    = "terraform.tfstate"
    region = "us-west-1"
  }
}
