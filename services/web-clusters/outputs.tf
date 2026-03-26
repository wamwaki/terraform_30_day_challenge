output "asg_name" {
  description = "the asg name"
  value = aws_autoscaling_group.terra_asg.name
}
output "alb_dns_name" {
  description = "dns name"
  value = aws_lb.terra_alb.dns_name
}
