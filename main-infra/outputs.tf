# outputs.tf
output "rds_endpoint" {
  description = "Connection endpoint for the MySQL RDS instance"
  value       = aws_db_instance.mysql.endpoint
}
