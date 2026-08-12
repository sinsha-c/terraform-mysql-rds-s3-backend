terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket-rds-demo"
    key            = "rds/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
