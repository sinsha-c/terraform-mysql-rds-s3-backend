# rds.tf
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-demo-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
 
  tags = {
    Name = "rds-demo-subnet-group"
  }
}
resource "aws_db_instance" "mysql" {
  identifier             = "rds-demo-mysql"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  storage_type           = "gp2"
 
  db_name                = "demodb"
  username               = var.db_username
  password               = var.db_password
 
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
 
  publicly_accessible    = false
  multi_az               = false
  skip_final_snapshot    = true
 
  tags = {
    Name = "rds-demo-mysql"
  }
}
