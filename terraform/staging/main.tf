# Terraform configuration

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

data "terraform_remote_state" "projectreclass-terraform-oregon" {
  backend = "s3"
  config = {
    encrypt = true
    bucket = "projectreclass-terraform-oregon"
    dynamodb_table = "terraform-state-lock"
    key    = "terraform.tfstate"
    region = "us-west-2"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

provider "aws" {
  region = "us-west-2"
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
    bucket = "projectreclass-terraform-oregon"
    key    = "terraform.tfstate"
    region = "us-west-2"
  }
}

############################################ Jumpbox ############################################

resource "aws_security_group" "jumpbox_stage_sg" {
  name        = "jumpbox-stage-sg"
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
  ami                  = "ami-01fee56b22f308154" # Amazon Linux 2 AMI
  instance_type        = "t2.nano"
  iam_instance_profile = aws_iam_instance_profile.ecs_agent_stage.name # to try to pull docker
  subnet_id            = module.vpc.public_subnets[0]
  security_groups      = [aws_security_group.jumpbox_stage_sg.id]
  key_name             = "toynet-key-theo-2020"
  user_data            = "#!/bin/bash\nsudo amazon-linux-extras install docker; sudo systemctl start docker;"

  associate_public_ip_address = true

  tags = {
    Name = "jumpbox"
  }
}

############################################ Container Policies & Roles ############################################

resource "aws_iam_role" "ecs_agent_stage" {
  name               = "ecs-agent_stage"
  assume_role_policy = data.aws_iam_policy_document.ecs_agent_stage_policydoc.json
}

data "aws_iam_policy_document" "ecs_agent_stage_policydoc" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_agent_stage" {
  role       = aws_iam_role.ecs_agent_stage.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_agent_stage" {
  name = "ecs-agent-stage"
  role = aws_iam_role.ecs_agent_stage.name
}

data "aws_iam_role" "ecs_task_execution_role_stage" {
  name = "ecsTaskExecutionRole"
}

data "aws_iam_role" "ecs_task_execution_role_django_stage" {
  name = "ecsTaskExecutionRole-toynet-django"
}

data "aws_iam_role" "ecs_service_role_stage" {
  name = "ecsServiceRole"
}

########## ToyNet React: Elastic Container Service Cluster ###########################################

resource "aws_security_group" "toynet_react_stage_sg" {
  name        = "toynet-react-stage-sg"
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

  depends_on        = [aws_instance.jumpbox_instance]
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
  execution_role_arn    = data.aws_iam_role.ecs_task_execution_role_stage.arn
}

resource "aws_ecs_cluster" "toynet_react_ecs_cluster" {
  name = "toynet-react-cluster"
}

resource "aws_ecs_service" "toynet_react_ecs_service" {
  name            = "toynet-react-service"
  iam_role        = data.aws_iam_role.ecs_service_role_stage.arn
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
  ami                  = "ami-01fee56b22f308154" # Amazon ECS Optimized
  instance_type        = "t2.medium"
  iam_instance_profile = aws_iam_instance_profile.ecs_agent_stage.name
  subnet_id            = module.vpc.public_subnets[0]
  security_groups      = [aws_security_group.toynet_react_stage_sg.id]
  key_name             = "toynet-key-theo-2020"
  user_data            = "#!/bin/bash\necho ECS_CLUSTER='toynet-react-cluster' >> /etc/ecs/ecs.config"

  associate_public_ip_address = true

  tags = {
    Name = "ecs-react-box"
  }
}

########## ToyNet React: Application Load Balancer ############################################

resource "aws_security_group" "toynet_react_lb_stage_sg" {
  name        = "toynet-react-lb-stage-sg"
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
  security_groups    = [aws_security_group.toynet_react_lb_stage_sg.id]
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

resource "aws_security_group" "toynet_django_stage_sg" {
  name        = "toynet-django-stage-sg"
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

  depends_on        = [aws_instance.jumpbox_instance]
}

data "template_file" "toynet_django_task_definition_file" {
  template = file("toynet-django-task-definition.json")
}

resource "aws_ecs_task_definition" "toynet_django_task_definition" {
  family                = "toynet-django"
  container_definitions = data.template_file.toynet_django_task_definition_file.rendered
  execution_role_arn    = data.aws_iam_role.ecs_task_execution_role_django_stage.arn
}

resource "aws_ecs_cluster" "toynet_django_ecs_cluster" {
  name = "toynet-django-cluster"
}

resource "aws_ecs_service" "toynet_django_ecs_service" {
  name            = "toynet-django-service"
  iam_role        = data.aws_iam_role.ecs_service_role_stage.arn
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
  ami                  = "ami-01fee56b22f308154" # Amazon ECS Optimized
  instance_type        = "t2.medium"
  iam_instance_profile = aws_iam_instance_profile.ecs_agent_stage.name
  subnet_id            = module.vpc.private_subnets[0]
  security_groups      = [aws_security_group.toynet_django_stage_sg.id]
  key_name             = "toynet-key-theo-2020"
  user_data            = "#!/bin/bash\necho ECS_CLUSTER='toynet-django-cluster' >> /etc/ecs/ecs.config"

  associate_public_ip_address = false

  tags = {
    Name = "ecs-django-box"
  }
}

########## ToyNet Django: Application Load Balancer ###########################################

resource "aws_security_group" "toynet_django_lb_stage_sg" {
  name        = "toynet-django-lb-stage-sg"
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
  security_groups    = [aws_security_group.toynet_django_lb_stage_sg.id]
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

# dynamodb table for state file locking
    resource "aws_dynamodb_table" "terraform_state_locking_dynamodb" {
      name = "terraform-state-locking"
      hash_key = "LockID"
      read_capacity = 20
      write_capacity = 20
     
      attribute {
        name = "LockID"
        type = "S"
      }
     
      tags = {
        Name = "Terraform State File Locking"
      }
    }
