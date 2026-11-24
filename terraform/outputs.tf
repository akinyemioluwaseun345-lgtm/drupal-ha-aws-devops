# outputs.tf
# Non-sensitive values you (and later, Ansible) will need. No passwords here.

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "availability_zones" {
  description = "Availability Zones used."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB, NAT Gateways)."
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "Private application subnet IDs (Drupal servers, EFS mount targets)."
  value       = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  description = "Private database subnet IDs (RDS)."
  value       = aws_subnet.private_db[*].id
}

output "alb_dns_name" {
  description = "DNS name of the load balancer. Open http://<this> in a browser."
  value       = aws_lb.app.dns_name
}

output "target_group_arn" {
  description = "ARN of the target group (useful when checking target health)."
  value       = aws_lb_target_group.app.arn
}

output "autoscaling_group_name" {
  description = "Name of the application Auto Scaling Group."
  value       = aws_autoscaling_group.app.name
}

output "app_security_group_id" {
  description = "Security group ID of the application servers."
  value       = aws_security_group.app.id
}

output "efs_file_system_id" {
  description = "ID of the shared EFS file system (use with the EFS mount helper)."
  value       = aws_efs_file_system.drupal.id
}

output "efs_dns_name" {
  description = "DNS name of the EFS file system."
  value       = aws_efs_file_system.drupal.dns_name
}

output "rds_endpoint" {
  description = "RDS endpoint in host:port form."
  value       = aws_db_instance.drupal.endpoint
}

output "rds_address" {
  description = "RDS hostname only (no port)."
  value       = aws_db_instance.drupal.address
}

output "db_name" {
  description = "Name of the Drupal database."
  value       = var.db_name
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the database credentials. Ansible reads the password from here."
  value       = aws_secretsmanager_secret.db.arn
}