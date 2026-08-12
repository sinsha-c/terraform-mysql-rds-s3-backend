# rds.tf
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-demo-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
 
  tags = {
    Name = "rds-demo-subnet-group"
  }
}
