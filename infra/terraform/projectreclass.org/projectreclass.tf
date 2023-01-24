provider "aws" {
  region = "us-east-2"
}

resource "aws_instance" "jumpbox_instance" {
  ami                  = "ami-04ce935d319474801" # projectreclass.org AMI
  instance_type        = "t2.nano"
  key_name             = "vault"
}
