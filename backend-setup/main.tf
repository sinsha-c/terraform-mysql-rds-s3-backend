# backend-setup/main.tf
 
resource "aws_s3_bucket" "terraform_state" {
  bucket = "my-terraform-state-bucket-rds-demo"   # must be globally unique — change this
 
  lifecycle {
    prevent_destroy = true
  }
 
  tags = {
    Name = "terraform-state-bucket"
  }
}
 
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
 
  versioning_configuration {
    status = "Enabled"
  }
}
 
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
 
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
 
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
 
  attribute {
    name = "LockID"
    type = "S"
  }
 
  tags = {
    Name = "terraform-state-lock-table"
  }
}
