provider "aws" {
  region = "us-east-2"
}

resource "aws_security_group" "hackday-test" {
  name        = "hackday-test"
  description = "allow ssh and http traffic"

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

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "Hackday-test" {
  ami               = "ami-0a54aef4ef3b5f881"
  instance_type     = "t2.micro"
  security_groups   = ["${aws_security_group.hackday-test.name}"]
  key_name = "toynet-key-theo-2020"
  user_data = <<-EOF
                #! /bin/bash
                sudo yum install httpd -y
                sudo systemctl start httpd
                sudo systemctl enable httpd
                echo '<h1 style=" text-align: center; font-family: cursive; ">Thank You for Coming to Project Reclass Hackday 2020 </h1>' > /var/www/html/index.html
  EOF


  tags = {
        Name = "Hackday Test Server"
  }

}
