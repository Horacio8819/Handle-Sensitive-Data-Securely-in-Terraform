# Handle Sensitive Data Securely in Terraform

The Three Leak Paths
Leak Path 1 — Hardcoded Secrets in .tf Files
If the Secrets such as Password or API key is written directly inside Terraform configuration files, they get committed to Git. Even if you remove them later, they remain in Git history forever. Anyone with repository Access can get Access to that.
Vulnerable pattern
resource "aws_db_instance" "example" {
  username = "admin"
  password = "super-secret-password"  #  exposed in code + Git history
}
Secure alternative
resource "aws_db_instance" "example" {
  username = "admin"
  password = var.db_password
}
variable "db_password" {
  type      = string
  sensitive = true
}
Leak Path 2 — Secrets in Variable Defaults or in Output
By defining a secret as a default value in a variable, it lives inside .tf files → meaning it’s committed to Git. If the Output or varibale are used as secret without marking them as sensitive Terraform will Display them in terminal and logs. 
Vulnerable pattern
variable "db_password" {
  default = "super-secret-password"  #  stored in source control
}
output "db_password" {
  value = var.db_password # Output the Passwort in plain text
}
Secure alternative
output "db_password" {
  value     = var.db_password
  sensitive = true
}
variable "db_password" {
  type      = string
  sensitive = true
}
by Setting sensitive = true Terraform Shows sensitive value instead of secret value.
Leak Path 3 — Plaintext Secrets in Terraform State
Terraform stores all resolved values (including secrets) in terraform.tfstate in plaintext. Therefore even if leaks paths 1 and 2 are respected, anyone with Access to state file can read Secrets. Local state file is risky. the best sulution for that is to secure state file in a secure backend. 
AWS Secrets Manager Integration
i first create database credentials in AWS Secrets Manager manually, so the secret never touch .tf files. 
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
The Secrets were then referenced in RDS as shown below:
resource "aws_db_instance" "example" {
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"
  db_name        = "appdb"
  username = local.db_credentials["username"]
  password = local.db_credentials["password"]
  db_subnet_group_name = aws_db_subnet_group.example.name
}
By Setting everything as shown above, the secret values never appeared in terraform configuration file. 
Sensitive Variable and Output Declarations
variable "db_password" {
  description = "Database administrator password"
  type        = string
  sensitive   = true
  # No default — Terraform will prompt or require TF_VAR_db_password
}
output "db_connection_string" {
  value     = "mysql://${aws_db_instance.example.username}@${aws_db_instance.example.endpoint}/${aws_db_instance.example.db_name}"
  sensitive = true
}
 As terraform meet sensitive value in Output it Shows: (sensitive value)
State File Security Audit
S3 Backend was used to secure terraform state file, since it encrypts data in tramsition and at rest. 
terraform {
  # S3 backend with encryption and restricted access
  backend "s3" {
    bucket         = "horacio-dfho-terraform-state-2026"
    key            = "production/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true  # AES-256 server-side encryption
  }
}
Secure check steps
Block all public access enabled
 S3 encryption enabled
 Bucket versioning enabled (to recover from accidental overwrites) 
Bucket policy restricting access to only the IAM roles that run Terraform
Only the users running terraform can write and read from the S3 bucket, The IAM Policy enforces the least Privilege.
.gitignore Contents and Explanation About each entry:
.terraform/ ---> provide binaries and locals terraform data
.terraform.lock.hcl ---> provide lock file 
*.tfstate* ---> contains infrastructure Details and secrets
*.tfvars* ---> contains sensitive Inputs
override.tf* ---> local overrides
Chapter 6 Learnings
sensitive = true does NOT prevent secrets in state. It only affects how Terraform displays values in the Outputs or logs, not how it stores them. 
HashiCorp Vault vs AWS Secrets Manager AWS Secrets Manager is suitable when working fully in AWS to store Secrets (DB Passwords, API keys)
Terraform may store the password to detect changes, to manage some resources, to void recreating resources unnecessarily, to compare and create resources.
