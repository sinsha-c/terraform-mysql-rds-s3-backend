# Provisioning an Amazon RDS (MySQL) Instance with a Terraform S3 Remote Backend
 
A beginner-friendly, hands-on Terraform project that provisions a **MySQL RDS instance** inside a custom VPC, while storing Terraform's state file remotely and safely in **Amazon S3** with **DynamoDB state locking**.
 
This project is designed for people who are **new to Terraform** — every step is explained in plain language, with placeholders for screenshots so you can follow along visually.
 
---
 
## Architecture Diagram
 
<img src="screenshots/architecture-diagram.png" alt="Architecture diagram: Terraform RDS with S3 remote backend" width="850">
The diagram shows the two halves of this project:
 
- **Terraform remote backend** (bottom) — an S3 bucket stores the state file, and a DynamoDB table locks it during `apply`.
- **Application infrastructure** (the VPC) — two private subnets host the RDS instance through a DB subnet group, and a security group is the only thing allowed to reach it, on port 3306.
---
 
## Why a Remote Backend?
 
If you're new to Terraform, you might be wondering why we don't just let Terraform save its state file (`terraform.tfstate`) on our own laptop (the default behavior). Here's why a **remote backend** matters:
 
- **Team collaboration** — Multiple people can safely work on the same infrastructure.
- **State locking** — DynamoDB prevents two `terraform apply` runs from corrupting the state at the same time.
- **Durability** — S3 is highly durable; you won't lose your state file if your laptop dies.
- **Security** — State files often contain sensitive data (like DB passwords); S3 lets you encrypt and restrict access.
---
 
## Prerequisites
 
Before starting, make sure you have:
 
- [ ] An **AWS account** with programmatic (CLI) access
- [ ] **AWS CLI** installed and configured (`aws configure`)
- [ ] **Terraform** installed (v1.5+ recommended) — [Download here](https://developer.hashicorp.com/terraform/downloads)
- [ ] Basic familiarity with the terminal/command line
- [ ] An IAM user/role with permissions for: S3, DynamoDB, VPC, RDS, EC2 (security groups)
 
---
 
## Project Structure
 
```
terraform-mysql-rds-s3-backend/
├── backend-setup/
│   ├── main.tf              # Creates the S3 bucket + DynamoDB table (run ONCE, separately)
│   ├── variables.tf
│   └── outputs.tf
│
├── main-infra/
│   ├── backend.tf            # Points Terraform to the S3 bucket + DynamoDB table
│   ├── provider.tf           # AWS provider configuration
│   ├── vpc.tf                # VPC + private subnets
│   ├── security-group.tf     # MySQL security group
│   ├── rds.tf                # RDS instance + DB subnet group
│   ├── variables.tf          # Input variables
│   ├── outputs.tf            # RDS endpoint output
│   └── terraform.tfvars      # Variable values (DO NOT commit passwords here in real projects)
│
└── README.md
```
 
> Note: We split this into two folders because the S3 bucket/DynamoDB table (the backend itself) must exist **before** Terraform can use them as a backend. You can't create the backend and use it in the very same `apply`.
 
---
 
## Step-by-Step Guide
 
### Step 1: Set Up the S3 Bucket + DynamoDB Table
 
This is a **one-time setup** step. Run this from the `backend-setup/` folder using Terraform's default **local** state (since the remote backend doesn't exist yet).
 
Yes — `main.tf` is required here. It's a normal Terraform file that defines the S3 bucket and DynamoDB table as regular resources. Because the remote backend doesn't exist yet, Terraform has no choice but to track this apply with a local `terraform.tfstate` file, sitting right next to this `main.tf`.
 
```hcl
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
```
 
```bash
cd backend-setup
terraform init
terraform plan
terraform apply
```
 
This creates:
- An S3 bucket (versioning + encryption enabled) to store `terraform.tfstate`
- A DynamoDB table with a primary key `LockID` (String) for state locking
> S3 bucket created in the AWS Console
>
> <img src="screenshots/s3-bucket-created.png" alt="S3 bucket in AWS Console" width="800">
 
> DynamoDB table created in the AWS Console
>
> <img src="screenshots/dynamodb-table-created.png" alt="DynamoDB table in AWS Console" width="800">
 
> Terraform apply output for backend-setup
>
> <img src="screenshots/backend-setup-apply-output.png" alt="terraform apply output" width="800">
 
---
 
### Step 2: Configure the Terraform Backend
 
Now move into `main-infra/` and point Terraform to the S3 bucket and DynamoDB table you just created, using a `backend.tf` file.
 
```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket-rds-demo"
    key            = "rds/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```
 
> Note: Bucket names must be **globally unique** across all of AWS. Change `my-terraform-state-bucket-rds-demo` to something unique to you.
 
> backend.tf file in your editor
>
> <img src="screenshots/backend-tf-file.png" alt="backend.tf configuration" width="700">

**One more file before moving on:** create `provider.tf` alongside it. The `region` set inside `backend "s3" {}` above only controls where the *state file* lives — it has no effect on where your actual resources (VPC, RDS, etc.) get created. Without a `provider` block, that decision falls back silently to whatever `AWS_REGION` is set, or your `~/.aws/config`, or — if you're running this from an EC2 instance with an IAM role and nothing else configured
 
```hcl
# provider.tf
provider "aws" {
  region = "apsouth-1"   # match this to the region you actually want your infrastructure in
}
```
 
At this point you can optionally run `terraform init` just to confirm Terraform connects to the S3 backend successfully:
 
```bash
terraform init
```
 
You should see `Successfully configured the backend "s3"!` in the output. There's nothing to `plan` or `apply` yet, though — `vpc.tf`, `security-group.tf`, and `rds.tf` don't exist until Steps 3–6, and the real `init` → `plan` → `apply` workflow for the full project happens together in Step 7.
 
---
