output "toynet_lb_domain" {
  description = "The DNS name associated with the application load balancer"
  value       = aws_lb.toynet_lb.dns_name
}
