terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

data "terraform_remote_state" "projectreclass-terraform-state-qa" {
  backend = "s3" 
  config = {
    bucket  = "projectreclass-terraform-state-qa"
    key     = "terraform.tfstate"
    encrypt = true
    region  = var.region
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ecs_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = [var.ecs_ami_name]
  }
}

provider "aws" {
  region = var.region
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
}

terraform {
  backend "s3" {
    bucket  = "projectreclass-terraform-state-qa"
    key     = "terraform.tfstate"
    encrypt = true
    region  = "us-east-1"
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
      identifiers = ["ec2.amazonaws.com", "ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_agent" {
  role       = aws_iam_role.ecs_agent.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_agent_ssm" {
  role       = aws_iam_role.ecs_agent.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs_agent" {
  name = "ecs-agent"
  role = aws_iam_role.ecs_agent.name
}

data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

data "aws_iam_role" "ecs_service_role" {
  name = "ecsServiceRole"
}

########## ToyNet: Elastic Container Service Cluster ###########################################

resource "aws_security_group" "toynet_sg" {
  name        = "toynet-sg"
  description = "allow ssh and http traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8888
    to_port     = 8888
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
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "template_file" "toynet_task_definition_file" {
  template = file("toynet-task-definition.json")
}

resource "aws_ecs_task_definition" "toynet_task_definition" {
  container_definitions = data.template_file.toynet_task_definition_file.rendered
  execution_role_arn    = data.aws_iam_role.ecs_task_execution_role.arn

  family = "ToyNet"
  requires_compatibilities = [
    "EC2"
  ]
  volume {
    name = "lib-modules"
    host_path = "/lib/modules"
  }
  volume {
    name = "docker-socket"
    host_path = "/var/run/docker.sock"
  }
}

resource "aws_ecs_cluster" "toynet_ecs_cluster" {
  name = "ToyNet"
}

resource "aws_ecs_service" "toynet_ecs_service" {
  name            = "toynet-service"
  iam_role        = data.aws_iam_role.ecs_service_role.arn
  cluster         = aws_ecs_cluster.toynet_ecs_cluster.id
  task_definition = aws_ecs_task_definition.toynet_task_definition.arn
  desired_count   = 2

  depends_on = [
    aws_alb_target_group.toynet_target_group,
    aws_lb.toynet_lb
  ]

  load_balancer {
    target_group_arn = aws_alb_target_group.toynet_target_group.arn
    container_name   = "frontend"
    container_port   = 80
  }
}

resource "aws_placement_group" "toynet_pg" {
  name          = "ToyNet Placement Group"
  strategy      = "spread"
}

resource "aws_launch_configuration" "toynet_launch_configuration" {
  name_prefix                 = "ECS-host"
  image_id                    = data.aws_ami.ecs_ami.id
  instance_type               = "t3.small"
  key_name                    = "blaze-infra"
  iam_instance_profile = aws_iam_instance_profile.ecs_agent.name

  user_data                   = base64encode("#!/bin/bash\n mkdir /etc/ecs \necho ECS_CLUSTER='ToyNet' >> /etc/ecs/ecs.config")
  associate_public_ip_address = true
  security_groups                = [aws_security_group.toynet_sg.id]
}

resource "aws_autoscaling_group" "toynet_autoscale_group" {
  name                  = "ToyNet Autoscale Group"
  max_size              = 2
  min_size              = 1
  health_check_type     = "EC2"
  desired_capacity      = 1
  vpc_zone_identifier   = [module.vpc.public_subnets[0]]
  target_group_arns     = [aws_alb_target_group.toynet_target_group.arn]

  launch_configuration = aws_launch_configuration.toynet_launch_configuration.name

  depends_on = [
    aws_alb_target_group.toynet_target_group,
    aws_lb.toynet_lb
  ]
}

########## ToyNet: Application Load Balancer ############################################

resource "aws_security_group" "toynet_lb_sg" {
  name        = "toynet-lb-sg"
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
resource "aws_lb" "toynet_lb" {
  name               = "toynet-lb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.toynet_lb_sg.id]
  subnets            = [module.vpc.public_subnets[0], module.vpc.public_subnets[1]]
}

# Target group
resource "aws_alb_target_group" "toynet_target_group" {
  name     = "toynet-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  stickiness {
    enabled     = true
    type        = "lb_cookie"
  }

  health_check {
    path                = "/"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 10
    interval            = 30
    matcher             = "200"
  }
}

resource "aws_alb_listener" "toynet_lb_httplistener" {
  load_balancer_arn = aws_lb.toynet_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.toynet_target_group.arn
  }
}
