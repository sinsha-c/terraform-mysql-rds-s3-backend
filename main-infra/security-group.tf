# security-group.tf
resource "aws_security_group" "rds_sg" {
  name        = "rds-mysql-sg"
  description = "Allow MySQL access from trusted source"
  vpc_id      = aws_vpc.main.id
 
  ingress {
    description = "MySQL access"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]   # Replace with your trusted CIDR or use security_groups = [aws_security_group.ec2_sg.id]
  }
 
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
 
  tags = {
    Name = "rds-mysql-sg"
  }
}
