# VPC — isolated virtual network for all resources
resource "aws_vpc" "terra_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.cluster_name}-vpc" }
}

# Public subnet 1 — in first AZ
resource "aws_subnet" "terra_oo1" {
  vpc_id                  = aws_vpc.terra_vpc.id
  cidr_block              = var.variables_sub_cidr
  availability_zone       = var.variables_sub_az
  map_public_ip_on_launch = var.variables_sub_auto_ip

  tags = { Name = "${var.cluster_name}-subnet_1" }
}

# Public subnet 2 — second AZ, required by ALB (needs 2 AZs minimum)
resource "aws_subnet" "terra_oo2" {
  vpc_id                  = aws_vpc.terra_vpc.id
  cidr_block              = var.variables_sub_cidr2
  availability_zone       = var.variables_sub_az2
  map_public_ip_on_launch = var.variables_sub_auto_ip

  tags = { Name = "${var.cluster_name}-subnet_2" }
}

# Internet Gateway — allows inbound and outbound internet traffic
resource "aws_internet_gateway" "terra_igw" {
  vpc_id = aws_vpc.terra_vpc.id
  tags   = { Name = "${var.cluster_name}-igw" }
}

# Route table — sends all traffic to the internet gateway
resource "aws_route_table" "terra_rt" {
  vpc_id = aws_vpc.terra_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.terra_igw.id
  }

  tags = { Name = "${var.cluster_name}-rt" }
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
  name   = "${var.cluster_name}-sg"
  vpc_id = aws_vpc.terra_vpc.id

  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = local.any_port
    to_port     = local.any_port
    protocol    = local.any_protocol
    cidr_blocks = local.all_ips
  }
}

# Security group for ALB — allows HTTP on port 80 and all outbound
resource "aws_security_group" "alb" {
  name   = "${var.cluster_name}-alb"
  vpc_id = aws_vpc.terra_vpc.id
}
resource "aws_security_group_rule" "allow_inbound" {
  type = "ingress"
  security_group_id = aws_security_group.alb.id

    from_port   = local.http_port
    to_port     = local.http_port
    protocol    = local.tcp_protocol
    cidr_blocks = local.all_ips
  }

resource "aws_security_group_rule" "outbound_rules" {
  type = "egress"
  security_group_id = aws_security_group.alb.id
    from_port   = local.any_port
    to_port     = local.any_port
    protocol    = local.any_protocol
    cidr_blocks = local.all_ips
  }
locals {
 http_port = 80
 any_port = 0
 any_protocol = "-1"
 tcp_protocol = "tcp"
 all_ips = ["0.0.0.0/0"]
}
# Random ID for unique S3 bucket name
resource "random_id" "randomness" {
  byte_length = 16
}

# Launch template — replaces deprecated aws_launch_configuration
resource "aws_launch_template" "terra_lt" {
  name          = "${var.cluster_name}-lt"
  image_id      = "ami-02dfbd4ff395f2a1b"
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.terra_sg.id]

  user_data = base64encode(templatefile("${path.module}/user-data.sh",{
    server_port = var.server_port
    db_address = data.terraform_remote_state.db.outputs.address
    db_port = data.terraform_remote_state.db.outputs.port
  }))

  # base64encode is required for launch templates unlike aws_instance


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
  min_size            = var.min_size
  max_size            = var.max_size

  launch_template {
    id      = aws_launch_template.terra_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-asg"
    propagate_at_launch = true
  }
}

# Application Load Balancer — spans both subnets across two AZs
resource "aws_lb" "terra_alb" {
  name               = "${var.cluster_name}-alb"
  load_balancer_type = "application"
  subnets            = [aws_subnet.terra_oo1.id, aws_subnet.terra_oo2.id]
  security_groups    = [aws_security_group.alb.id]
}

# ALB listener — listens on port 80, returns 404 by default
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.terra_alb.arn
  port              = local.http_port
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
  name     = "${var.cluster_name}-tg"
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


data "terraform_remote_state" "db" {
  backend = "s3"
  config = {
    bucket = var.db_remote_state_bucket
    key = var.db_remote_state_key
    region = "us-east-1"
  }
}