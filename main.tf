terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Provider — downloads AWS plugin on terraform init
provider "aws" {
  region = var.aws_region
}

# Current region data source
data "aws_region" "current" {}

# VPC — isolated virtual network for all resources
resource "aws_vpc" "terra_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "terra_vpc" }
}

# Public subnet 1 — in first AZ
resource "aws_subnet" "terra_oo1" {
  vpc_id                  = aws_vpc.terra_vpc.id
  cidr_block              = var.variables_sub_cidr
  availability_zone       = var.variables_sub_az
  map_public_ip_on_launch = var.variables_sub_auto_ip

  tags = { Name = "terra_subnet_1" }
}

# Public subnet 2 — second AZ, required by ALB (needs 2 AZs minimum)
resource "aws_subnet" "terra_oo2" {
  vpc_id                  = aws_vpc.terra_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = { Name = "terra_subnet_2" }
}

# Internet Gateway — allows inbound and outbound internet traffic
resource "aws_internet_gateway" "terra_igw" {
  vpc_id = aws_vpc.terra_vpc.id
  tags   = { Name = "terra_igw" }
}

# Route table — sends all traffic to the internet gateway
resource "aws_route_table" "terra_rt" {
  vpc_id = aws_vpc.terra_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.terra_igw.id
  }

  tags = { Name = "terra_rt" }
}

# Associate route table with subnet 1
resource "aws_route_table_association" "terra_rta1" {
  subnet_id      = aws_subnet.terra_oo1.id
  route_table_id = aws_route_table.terra_rt.id
}

# Associate route table with subnet 2
resource "aws_route_table_association" "terra_rta2" {
  subnet_id      = aws_subnet.terra_oo2.id
  route_table_id = aws_route_table.terra_rt.id
}

# Security group for EC2 instances — allows app port and all outbound
resource "aws_security_group" "terra_sg" {
  name   = "terra-sg"
  vpc_id = aws_vpc.terra_vpc.id

  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
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

# Security group for ALB — allows HTTP on port 80 and all outbound
resource "aws_security_group" "alb" {
  name   = "terra_alb_sg"
  vpc_id = aws_vpc.terra_vpc.id

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

# Random ID for unique S3 bucket name
resource "random_id" "randomness" {
  byte_length = 16
}

# S3 bucket with unique name
resource "aws_s3_bucket" "terra_s3" {
  bucket = "my-new-terra-tb-${random_id.randomness.hex}"
}

# Launch template — replaces deprecated aws_launch_configuration
resource "aws_launch_template" "terra_lt" {
  name          = "terra-lt"
  image_id      = "ami-02dfbd4ff395f2a1b"
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.terra_sg.id]

  # base64encode is required for launch templates unlike aws_instance
  user_data = base64encode(<<-EOF
#!/bin/bash
mkdir -p /var/www
echo "Hello, world" > /var/www/index.html
cd /var/www && nohup python3 -m http.server ${var.server_port} &
EOF
  )

  lifecycle {
    create_before_destroy = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name      = "terra-lt-instance"
      Terraform = "true"
    }
  }
}

# Auto Scaling Group — references launch template instead of launch configuration
resource "aws_autoscaling_group" "terra_asg" {
  vpc_zone_identifier = [aws_subnet.terra_oo1.id, aws_subnet.terra_oo2.id]
  target_group_arns   = [aws_lb_target_group.asg.arn]
  health_check_type   = "ELB"
  min_size            = 2
  max_size            = 10

  launch_template {
    id      = aws_launch_template.terra_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "terra-asg"
    propagate_at_launch = true
  }
}

# Application Load Balancer — spans both subnets across two AZs
resource "aws_lb" "terra_alb" {
  name               = "Terraform-alb"
  load_balancer_type = "application"
  subnets            = [aws_subnet.terra_oo1.id, aws_subnet.terra_oo2.id]
  security_groups    = [aws_security_group.alb.id]
}

# ALB listener — listens on port 80, returns 404 by default
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.terra_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

# Target group — routes traffic to instances on the server port
resource "aws_lb_target_group" "asg" {
  name     = "aws-lb-target-group"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.terra_vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Listener rule — forwards all traffic matching /* to the target group
resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

# Output the ALB DNS name — use this to access the app in the browser
output "alb_dns_name" {
  value = aws_lb.terra_alb.dns_name
}