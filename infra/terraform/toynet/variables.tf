# Input variable defintions

variable "region" {
  description = "Region to deploy in"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
  default     = "vpc-04fc2565f55def422"
}

variable "vpc_name" {
  description = "Name of VPC"
  type        = string
  default     = "toynet-vpc"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_private_subnets" {
  description = "Private subnets for VPC"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "vpc_public_subnets" {
  description = "Public subnets for VPC"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "vpc_enable_nat_gateway" {
  description = "Enable NAT gateway for VPC"
  type    = bool
  default = true
}

variable "ecs_ami_name" {
  description = "Regex for selecting the ECS optimized AMI"
  type = string
  default = "amzn-ami-*-amazon-ecs-optimized"
}

variable "linux_ami_name" {
  description = "Regex for selecting a generic Linux AMI"
  type = string
  default ="amzn2-ami-kernel-*-x86_64-gp2"
}
