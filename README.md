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

> `key` isn't a credential — it's just the file path *inside* the S3 bucket where this project's state file will be stored.

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

> <img src="screenshots/backend-tf-init.png" alt="backend.tf configuration init" width="700">

---

### Step 3: Create the VPC and Private Subnets
 
We create a dedicated VPC with **two private subnets** in different Availability Zones (RDS requires a minimum of 2 AZs for its subnet group, even for a single-AZ instance).
 
Save this as `vpc.tf` inside `main-infra/` (alongside the `backend.tf` and `provider.tf` you created in Step 2):
 
```hcl
# vpc.tf
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
 
  tags = {
    Name = "rds-demo-vpc"
  }
}
 
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-south-1a"
 
  tags = {
    Name = "rds-private-subnet-1"
  }
}
 
resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1a"
 
  tags = {
    Name = "rds-private-subnet-2"
  }
}
```
 
> Screenshot placeholder: VPC and subnets visible in AWS Console
>
> `<img src="screenshots/vpc-subnets-created.png" alt="VPC and private subnets" width="800">`
 
Don't run `terraform apply` yet — `main-infra/` isn't finished. Keep adding files through Step 6 (DB subnet group, security group, RDS instance), and Step 7 covers running `init` → `plan` → `apply` once for the whole set at once.
 
---
 
### Step 4: Create the DB Subnet Group
 
A **DB Subnet Group** tells RDS exactly which subnets it is allowed to place the database's network interfaces in.
 
Save this as `rds.tf` inside `main-infra/` — this is the same file the RDS instance itself and the endpoint output will go into (Step 6 adds to it):
 
```hcl
# rds.tf
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-demo-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
 
  tags = {
    Name = "rds-demo-subnet-group"
  }
}
```
 
> DB Subnet Group in RDS Console
>
> <img src="screenshots/db-subnet-group.png" alt="DB Subnet Group" width="800">
 
---
 
### Step 5: Create the Security Group
 
This firewall rule allows inbound traffic **only on port 3306 (MySQL)**, restricted to a specific CIDR block or an EC2 security group — never open it to `0.0.0.0/0` in a real environment.
 
Save this as `security-group.tf` inside `main-infra/`:
 
```hcl
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
```
 
> Security Group inbound rules
>
> <img src="screenshots/security-group-rules.png" alt="Security Group MySQL rule" width="800">
 
---