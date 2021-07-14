terraform {
  required_providers {
    aws = "~> 3.27"
  }

  required_version = ">= 0.12.11"
}

provider "aws" {
  profile = "default"
  region  = "us-west-2"
}

// VPC and Subnet resources
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "main_vpc"
  }
}

resource "aws_subnet" "main_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  availability_zone = "us-west-2a"
  cidr_block        = "10.0.0.0/16"

  tags = {
    Name = "main_subnet"
  }
}

resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "main_igw"
  }
}

resource "aws_route_table" "main_sn_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "main_route_table"
  }
}

resource "aws_route_table_association" "sn_assc" {
  subnet_id      = aws_subnet.main_subnet.id
  route_table_id = aws_route_table.main_sn_route_table.id
}

resource "aws_security_group" "pr-sg" {
  name   = "new-sg"
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

// EC2 Instance Resources
resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCRLVO/JZdiEeAjDKS/xZRadYqdThAVCjb8Ci8Go/RWqASXlD4/IpK48ImsUBy5CIgBR5vZuxlyzf8OLgRmzsfDUxojZFesNCBs01eAmNNt565Wfo/plm4ROmf7TbpMBA87zoK754lk1edzRUZ4JK2mY/xmpkcbY/u0pQ6gIA6QK7O9KsFcpVDU1A6IWstR/gMBq7jjKU3NYt2QasBoTSsxzZOr/33VYEbvGB6gYnd9tjdv4kCHAml58ZtuRd+FXi0qWezTgv9CdiFmcTW8yFXFKNKAHd65cMJXx5MM4dxwuXqrwoNZkwxqcySJyqHuSom+bEHnqHhir0+ddOw70q/D p1-bonus-key"
}

resource "aws_instance" "server" {
  ami                    = "ami-0dc8f589abe99f538"
  instance_type          = "t2.micro"
  iam_instance_profile   = "CodeDeployDemo-EC2-Instance-Profile"
  key_name               = "deployer-key"
  subnet_id              = aws_subnet.main_subnet.id
  vpc_security_group_ids = [aws_security_group.pr-sg.id]


  //depends_on = [aws_internet_gateway.main_igw]
  tags = {
    Name = "project1-bonus-instance"
  }
}
