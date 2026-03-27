variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_name" {
  type    = string
  default = "demo_vpc"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "private_subnets" {
  default = {
    "private_subnet_1" = 1
    "private_subnet_2" = 2
    "private_subnet_3" = 3
  }
}

variable "public_subnets" {
  default = {
    "public_subnet_1" = 1
    "public_subnet_2" = 2
    "public_subnet_3" = 3
  }
}
variable "variables_sub_cidr" {
    description = "CIDR block for the variables subnet"
    type = string
    default = "10.0.0.0/24"
}
variable "variables_sub_cidr2" {
    description = "CIDR block for the variables subnet"
    type = string
    default = "10.0.2.0/24"
}
variable "variables_sub_az" {
  description = "Availability zone used variable subnet"
  type = string
  default = "us-east-1a"
}
variable "variables_sub_az2" {
  description = "Availability zone used variable subnet"
  type = string
  default = "us-east-1b"
}
variable "variables_sub_auto_ip" {
  description = "Set automatic iP assignment for variable subnet"
  type = bool
  default = true

}
variable "server_port" {
 description = "port used"
 type = number
 default = 8080
}
variable "cluster_name" {
  description = "for all cluster resources"
  type = string
}
variable "db_remote_state_bucket" {
  description = "name of s3 bucket"
  type = string
}
variable "db_remote_state_key" {
  description = "path for db remote state"
  type = string
}
variable "instance_type" {
  description = "type of instance to run"
  type = string
}
variable "min_size" {
  description = "min number of instances"
  type = number
}
variable "max_size" {
  description = "max number to run"
  type = number
}
variable "custom_tags" {
  description = "custom tags"
  type = map(string)
  default = {}
}
variable "enable_autoscaling" {
  description = "If set to try, allow autoscaling"
  type = bool
}
variable "domain_name" {
  description = "Route53 hosted zone domain name"
  type        = string
  default     = ""
}
variable "enable_detailed_monitoring" {
  description = "Enable CloudWatch detailed monitoring (incurs additional cost)"
  type        = bool
  default     = false
}

variable "create_dns_record" {
  description = "Whether to create a Route53 DNS record for the ALB"
  type        = bool
  default     = false
}
