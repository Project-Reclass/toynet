output "toynet_react_alb_domain" {
  description = "The DNS name associated with the react application load balancer"
  value       = aws_lb.toynet_react_alb.dns_name
}