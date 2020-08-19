# Creating a new VPC

provider "aws" {
  region = "us-east-2"
}

resource "aws_vpc" "hackday" {
  cidr_block = "192.1.0.0/16"
  tags = { 
    Name = "HackDay VPC"
  }
}

# Creating a gateway

resource "aws_internet_gateway" "hackdaygateway" {
  vpc_id = aws_vpc.hackday.id
}

# Creating a subnet

resource "aws_subnet" "main" {
  vpc_id = aws_vpc.hackday.id
  cidr_block = "192.1.1.0/24"
  availability_zone = "us-east-2b"
}

# Creating a route table

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.hackday.id

  route {
  cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.hackdaygateway.id
  }
}

resource "aws_route_table_association" "main" {
  subnet_id = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# Creating an ACL

resource "aws_network_acl" "allowall" {
  vpc_id = aws_vpc.hackday.id
  
  egress {
    protocol = "-1"
    rule_no = 100
    action = "allow"
    cidr_block = "0.0.0.0/0"
    from_port = 0
    to_port = 0
  } 

  ingress {
    protocol = "-1"
    rule_no = 200
    action = "allow"
    cidr_block = "0.0.0.0/0"
    from_port = 0
    to_port = 0
  }
}

# Creating a Security Group

resource "aws_security_group" "allowall" {
  name = "HackDay Allow All"
  description = "Allows all traffic - badpractice"
  vpc_id = aws_vpc.hackday.id

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
 }

  egress {
   from_port = 0
   to_port = 0
   protocol = "-1"
   cidr_blocks = ["0.0.0.0/0"]
 }
}

# Creating EIP 

resource "aws_eip" "hackdaywordpress" {
  instance = aws_instance.hackdaywordpress.id
  vpc = true
  depends_on = [aws_internet_gateway.hackdaygateway]
}

# Attaching SSH credentials

resource "aws_key_pair" "default" {
  key_name = "hackdayfakekey"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDTQ/Sf1w1hLmmhxs53HJ1uYoYeLVKjBb6CC8coyYe9Vs/GQDMfMBIJHRz0HGyH+Sp22SSqid3HJ0QiOK8EJBCvqwjkzx6fvnbY90ag7mxxrZH639+uLqYtSLH5Cd90HqZAKaDEvJtoS4lFIk96moeS1wyOVv33PS510/i8ihov7xlIMsqw83jVReZdpiiYM3qIO5IwsIluqoOoM5vwxxOwHeUNkAL4ZW4pLmwL1kv8UAi31kUpRCYHO2WxCRaQwEeWp8P0G7I+ptMQNXUC69QB/GofRKwQhiJRM8ukH9V+ABxyIdrIjfZbVk5vhCS6lKnT1WYv84ILAN0ZbcJQ6+3zLiZzVtzAF2eELPVNFmrG/hiNAP//NvPPReGY7KShNVqWCYxW7FlFXK9u0g1nIH1eyrK3pp/kQW2XgZZScsNUzvXLCyu/ORYEqR68cy8YasOQu/XIyveDJY7Mieg8S+Dkg3ArBy6LM2xjjN18sNfhyQVrduX9efxCxsLOWTzvunM= lint@Luffy"
}

data "aws_ami" "bitnami" {
  most_recent = true 

  filter {
    name = "name"
    values = ["bitnami-wordpress-5.4.2-1-linux-debian-10-x86_64-*"]
  }

  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["679593333241"]
}

resource "aws_instance" "hackdaywordpress" {
  ami = data.aws_ami.bitnami.id 
  availability_zone = "us-east-2b"
  instance_type = "t2.micro"
  key_name = aws_key_pair.default.key_name
  vpc_security_group_ids = [aws_security_group.allowall.id]
  subnet_id = aws_subnet.main.id
}

output "public_ip" {
  value = aws_eip.hackdaywordpress.public_ip
}

