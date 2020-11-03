# Terraform configuration

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.21.0"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs             = var.vpc_azs
  private_subnets = var.vpc_private_subnets
  public_subnets  = var.vpc_public_subnets

  enable_nat_gateway = var.vpc_enable_nat_gateway

  tags = var.vpc_tags
}

resource "aws_s3_bucket" "tf_state_test" {
  # Unique bucket name 
  bucket = "projectreclass-test-bucket"

  # Prevent accidental deletion of tf state
  lifecycle {
    prevent_destroy = true
  }

  # Enable Versioning to track history 
  versioning {
    enabled = true
  }

  # Enable Encryption
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

terraform {
  backend "s3" {
    # S3 Bucket Details
    # Must match bucket name
    bucket = "projectreclass-test-bucket"
    # Name to assign to the state file
    key = "test/tf.state"
    # region the bucket is in
    region = "us-east-1"

    # DynamoDB Details
    dynamodb_table = "db_for_tf_locks_test"
    encrypt        = true
    depends_on     = [aws_dynamodb_table.tf_locks_test]
  }
}

############################################ Jumpbox ############################################

resource "aws_security_group" "jumpbox_sg" {
  name        = "jumpbox-sg"
  description = "allow ssh"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24", "10.0.2.0/24", "10.0.101.0/24", "10.0.102.0/24"]
  }
}

resource "aws_instance" "jumpbox_instance" {
  ami                  = "ami-0669eafef622afea1" # Amazon Linux 2 AMI ecs optimized
  instance_type        = "t2.nano"
  iam_instance_profile = aws_iam_instance_profile.ecs_agent.name # to try to pull docker
  subnet_id            = module.vpc.public_subnets[0]
  security_groups      = [aws_security_group.jumpbox_sg.id]
  key_name             = "Key"
  user_data            = "#!/bin/bash\nsudo amazon-linux-extras install docker; sudo systemctl start docker;"

  associate_public_ip_address = true

  tags = {
    Name = "jumpbox"
  }
}

############################################ Container Policies & Roles ############################################

resource "aws_iam_role" "ecs_agent" {
  name               = "ecs-agent"
  assume_role_policy = data.aws_iam_policy_document.ecs_agent_policydoc.json
}

data "aws_iam_policy_document" "ecs_agent_policydoc" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_agent" {
  role       = aws_iam_role.ecs_agent.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_agent" {
  name = "ecs-agent"
  role = aws_iam_role.ecs_agent.name
}

data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

data "aws_iam_role" "ecs_task_execution_role_django" {
  name = "ecsTaskExecutionRole-toynet-django"
}

data "aws_iam_role" "ecs_service_role" {
  name = "ecsServiceRole"
}

########## ToyNet React: Elastic Container Service Cluster ###########################################

resource "aws_security_group" "toynet_react_sg" {
  name        = "toynet-react-sg"
  description = "allow ssh and http traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.jumpbox_instance.private_ip}/32"]
  }

  ingress {
    from_port   = 20000
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24", "10.0.2.0/24", "10.0.101.0/24", "10.0.102.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  depends_on = [aws_instance.jumpbox_instance]
}

data "template_file" "toynet_react_task_definition_file" {
  template = file("toynet-react-task-definition.json")
  vars = {
    DJANGO_SERVER_URI = aws_lb.toynet_django_alb.dns_name
  }
}

resource "aws_ecs_task_definition" "toynet_react_task_definition" {
  family                = "toynet-react"
  container_definitions = data.template_file.toynet_react_task_definition_file.rendered
  execution_role_arn    = data.aws_iam_role.ecs_task_execution_role.arn
}

resource "aws_ecs_cluster" "toynet_react_ecs_cluster" {
  name = "toynet-react-cluster"
}

resource "aws_ecs_service" "toynet_react_ecs_service" {
  name            = "toynet-react-service"
  iam_role        = data.aws_iam_role.ecs_service_role.arn
  cluster         = aws_ecs_cluster.toynet_react_ecs_cluster.id
  task_definition = aws_ecs_task_definition.toynet_react_task_definition.arn
  desired_count   = 2

  depends_on = [
    aws_alb_target_group.toynet_react_target_group,
    aws_lb.toynet_react_alb
  ]

  load_balancer {
    target_group_arn = aws_alb_target_group.toynet_react_target_group.arn
    container_name   = "toynet-react-container"
    container_port   = 80
  }

}

resource "aws_instance" "toynet_react_container_instance" {
  ami                  = "ami-0669eafef622afea1" # Amazon ECS Optimized
  instance_type        = "t2.medium"
  iam_instance_profile = aws_iam_instance_profile.ecs_agent.name
  subnet_id            = module.vpc.public_subnets[0]
  security_groups      = [aws_security_group.toynet_react_sg.id]
  key_name             = "Key"
  user_data            = "#!/bin/bash\necho ECS_CLUSTER='toynet-react-cluster' >> /etc/ecs/ecs.config"

  associate_public_ip_address = true

  tags = {
    Name = "ecs-react-box"
  }
}

########## ToyNet React: Application Load Balancer ############################################

resource "aws_security_group" "toynet_react_lb_sg" {
  name        = "toynet-react-lb-sg"
  description = "allow HTTP and HTTPS"
  vpc_id      = module.vpc.vpc_id

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

# Production Load Balancer
resource "aws_lb" "toynet_react_alb" {
  name               = "toynet-react-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.toynet_react_lb_sg.id]
  subnets            = [module.vpc.public_subnets[0], module.vpc.public_subnets[1]]
}

# Target group
resource "aws_alb_target_group" "toynet_react_target_group" {
  name     = "toynet-react-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    path                = "/"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 10
    interval            = 300
    matcher             = "200"
  }
}

resource "aws_alb_listener" "toynet_react_alb_httplistener" {
  load_balancer_arn = aws_lb.toynet_react_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.toynet_react_target_group.arn
  }
}

########## ToyNet Django: Elastic Container Service Cluster ##########################################

resource "aws_security_group" "toynet_django_sg" {
  name        = "toynet-django-sg"
  description = "allow ssh and http traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.jumpbox_instance.private_ip}/32"]
  }

  ingress {
    from_port   = 20000
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24", "10.0.2.0/24", "10.0.101.0/24", "10.0.102.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  depends_on = [aws_instance.jumpbox_instance]
}

data "template_file" "toynet_django_task_definition_file" {
  template = file("toynet-django-task-definition.json")
}

resource "aws_ecs_task_definition" "toynet_django_task_definition" {
  family                = "toynet-django"
  container_definitions = data.template_file.toynet_django_task_definition_file.rendered
  execution_role_arn    = data.aws_iam_role.ecs_task_execution_role_django.arn
}

resource "aws_ecs_cluster" "toynet_django_ecs_cluster" {
  name = "toynet-django-cluster"
}

resource "aws_ecs_service" "toynet_django_ecs_service" {
  name            = "toynet-django-service"
  iam_role        = data.aws_iam_role.ecs_service_role.arn
  cluster         = aws_ecs_cluster.toynet_django_ecs_cluster.id
  task_definition = aws_ecs_task_definition.toynet_django_task_definition.arn
  desired_count   = 1

  depends_on = [
    aws_alb_target_group.toynet_django_target_group,
    aws_lb.toynet_django_alb
  ]

  load_balancer {
    target_group_arn = aws_alb_target_group.toynet_django_target_group.arn
    container_name   = "toynet-django-container"
    container_port   = 8000
  }
}

resource "aws_instance" "toynet_django_container_instance" {
  ami                  = "ami-0669eafef622afea1" # Amazon ECS Optimized
  instance_type        = "t2.medium"
  iam_instance_profile = aws_iam_instance_profile.ecs_agent.name
  subnet_id            = module.vpc.private_subnets[0]
  security_groups      = [aws_security_group.toynet_django_sg.id]
  key_name             = "Key"
  user_data            = "#!/bin/bash\necho ECS_CLUSTER='toynet-django-cluster' >> /etc/ecs/ecs.config"

  associate_public_ip_address = false

  tags = {
    Name = "ecs-django-box"
  }
}

########## ToyNet Django: Application Load Balancer ###########################################

resource "aws_security_group" "toynet_django_lb_sg" {
  name        = "toynet-django-lb-sg"
  description = "allow port 8000"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 8000
    to_port     = 8000
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

# Production Load Balancer
resource "aws_lb" "toynet_django_alb" {
  name               = "toynet-django-alb"
  load_balancer_type = "application"
  internal           = true
  security_groups    = [aws_security_group.toynet_django_lb_sg.id]
  subnets            = [module.vpc.private_subnets[0], module.vpc.private_subnets[1]]
}

# Target group
resource "aws_alb_target_group" "toynet_django_target_group" {
  name     = "toynet-django-tg"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    path                = "/healthcheck/"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 10
    interval            = 300
    matcher             = "200"
  }
}

# Listener (redirects traffic from the load balancer to the target group)
resource "aws_alb_listener" "toynet-django-alb-listener" {
  load_balancer_arn = aws_lb.toynet_django_alb.id
  port              = "8000"
  protocol          = "HTTP"
  depends_on        = [aws_alb_target_group.toynet_django_target_group]

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.toynet_django_target_group.arn
  }
}


