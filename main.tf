provider "aws" {
  region = "eu-central-1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # S3 backend with encryption and restricted access
  backend "s3" {
    bucket         = "horacio-dfho-terraform-state-2026"
    key            = "production/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true  # AES-256 server-side encryption
  }
}



data "aws_secretsmanager_secret" "db_credentials" {
  name = "prod/db/credentials"
}

data "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = data.aws_secretsmanager_secret.db_credentials.id
}

locals {
  db_credentials = jsondecode(
    data.aws_secretsmanager_secret_version.db_credentials.secret_string
  )
}
resource "aws_db_subnet_group" "example" {
  name = "example-db-subnet-group"

  subnet_ids = [
    aws_subnet.private_a.id, # eu-central-1a
    aws_subnet.private_b.id  # eu-central-1b
  ]

  tags = {
    Name = "example-db-subnet-group"
  }
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-central-1a"
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-central-1b"
}

resource "aws_db_instance" "example" {
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"
  db_name        = "appdb"

  username = local.db_credentials["username"]
  password = local.db_credentials["password"]

  # Additional required fields
  allocated_storage = 10
  skip_final_snapshot = true
  db_subnet_group_name = aws_db_subnet_group.example.name
}

variable "db_username" {
  description = "Database administrator username"
  type        = string
  sensitive   = true
}


variable "db_password" {
  description = "Database administrator password"
  type        = string
  sensitive   = true
  # No default — Terraform will prompt or require TF_VAR_db_password
}

output "db_connection_string" {
  value     = "mysql://${aws_db_instance.example.username}@${aws_db_instance.example.endpoint}/${aws_db_instance.example.db_name}"
  sensitive = true
}


