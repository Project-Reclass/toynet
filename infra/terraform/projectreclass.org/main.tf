terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = "us-east-2"
}

resource "aws_key_pair" "deployer" {
  key_name   = "new-kp"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7CLfU483omKfTo3Gp/iokagzvbp7NSCVA6C1o3ymd7WNXsDrn9sbR3Xomb/XO0ug9bSXjBBrNZ/dt/nKkELYS0QA+Pv2du/TcXThpA1khQZKihUdvl2k5ka1SuGUZvXij32a37s3bbZK7t09tM2GMgIZl6fqpo+Gqi1BXM20tOQBouwkeDA8sRWrIHV7n/Fa/Aypbqp0Q+VzoG5/ECVmZaLoGrK+08vE3ULvkN0QWwoXcOBMcoe4Plq3Nt5vubgEJmZKT2NhllDaVrXHSYYYQ0JxAYQklGBzF/cK7uSxUh4hJtsDsl0TYYMYOjSYewW31jOF8rVpcRD8QrVtVJ2WV new-kp"
}

resource "aws_instance" "app_server" {
  ami           = "ami-0385fb77199a3e724" # This has the website in it; seems a little off from the real one but backup restore should handle it
  instance_type = "t2.micro"
  iam_instance_profile = "CodeDeployDemo-EC2-Instance-Profile"
  key_name = "new-kp"
  vpc_security_group_ids = ["sg-0104b7c63301a7d1c"]	 # This is not the site SG we actually use

  tags = {
    Name = "p1-projectreclass.org"
  }
}
