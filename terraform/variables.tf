# variables.tf
# All input variables. Values for this project are set in terraform.tfvars.

# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project name used as a prefix in resource names (lowercase letters, numbers, hyphens)."
  type        = string
  default     = "drupal-ha"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-16 characters: lowercase letters, numbers and hyphens, starting with a letter and not ending with a hyphen (keeps AWS resource names within length limits)."
  }
}

variable "environment" {
  description = "Environment name (for example dev, test, prod). Used in names and tags."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,6}[a-z0-9]$", var.environment))
    error_message = "environment must be 2-8 characters: lowercase letters, numbers and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "additional_tags" {
  description = "Extra tags to add to all resources (for example Owner or Course)."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must be between /8 and /16 because subnets are carved out as /24 blocks."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/(8|9|1[0-6])$", var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR with a prefix length between /8 and /16 (for example 10.0.0.0/16)."
  }
}

variable "az_count" {
  description = "Number of Availability Zones to use (the assignment needs at least 2)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "nat_gateway_per_az" {
  description = "true = one NAT Gateway per AZ (highly available, about double the NAT cost). false = a single shared NAT Gateway (cheaper, but an AZ failure there removes outbound internet for all app servers)."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Application servers (EC2 + Auto Scaling)
# -----------------------------------------------------------------------------
variable "instance_type" {
  description = "EC2 instance type for the Drupal application servers."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size_gb" {
  description = "Size in GB of each application server's encrypted root volume."
  type        = number
  default     = 20
}

variable "asg_min_size" {
  description = "Minimum number of application servers."
  type        = number
  default     = 2

  validation {
    condition     = var.asg_min_size >= 2
    error_message = "asg_min_size must be at least 2 for high availability."
  }
}

variable "asg_desired_capacity" {
  description = "Desired number of application servers."
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of application servers."
  type        = number
  default     = 4
}

variable "asg_health_check_type" {
  description = "EC2 = replace instances only when the VM itself fails. ELB = also replace instances that fail the load balancer health check. Keep EC2 until Ansible has installed Drupal, then switch to ELB."
  type        = string
  default     = "EC2"

  validation {
    condition     = contains(["EC2", "ELB"], var.asg_health_check_type)
    error_message = "asg_health_check_type must be either EC2 or ELB."
  }
}

variable "asg_health_check_grace_period" {
  description = "Seconds the Auto Scaling Group waits after launch before checking an instance's health."
  type        = number
  default     = 300
}

variable "enable_instance_db_secret_read" {
  description = "Allow the application servers' IAM role to read ONLY the database secret in Secrets Manager (useful if Ansible runs on the instances). Set false if Ansible runs from your own machine."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Load balancer
# -----------------------------------------------------------------------------
variable "app_port" {
  description = "Port the web server on the application servers listens on."
  type        = number
  default     = 80
}

variable "alb_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the load balancer on port 80. Restrict to your own IP while testing if you prefer."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "health_check_path" {
  description = "HTTP path the load balancer requests to check instance health."
  type        = string
  default     = "/"
}

variable "health_check_matcher" {
  description = "HTTP status codes counted as healthy. A fresh Drupal site often redirects (302) to the installer, so redirects are accepted."
  type        = string
  default     = "200-399"
}

variable "health_check_interval" {
  description = "Seconds between load balancer health checks."
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------
# Database (RDS MySQL)
# -----------------------------------------------------------------------------
variable "db_name" {
  description = "Name of the initial database created for Drupal."
  type        = string
  default     = "drupal"
}

variable "db_username" {
  description = "Master username for the database. The password is generated automatically."
  type        = string
  default     = "drupal_admin"
}

variable "db_engine_version" {
  description = "MySQL major/minor engine version. Using 8.0 lets AWS pick the current 8.0 minor release."
  type        = string
  default     = "8.0"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Initial database storage in GB."
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Upper limit in GB for automatic storage growth. Set to 0 to disable storage autoscaling."
  type        = number
  default     = 100
}

variable "db_port" {
  description = "Port the database listens on."
  type        = number
  default     = 3306
}

variable "db_multi_az" {
  description = "Create a standby database in a second AZ (required by the assignment)."
  type        = bool
  default     = true
}

variable "db_backup_retention_period" {
  description = "Days to keep automated backups (1-35)."
  type        = number
  default     = 7

  validation {
    condition     = var.db_backup_retention_period >= 1 && var.db_backup_retention_period <= 35
    error_message = "db_backup_retention_period must be between 1 and 35 so automated backups stay enabled."
  }
}

variable "db_backup_window" {
  description = "Daily UTC time window for automated backups."
  type        = string
  default     = "03:00-04:00"
}

variable "db_maintenance_window" {
  description = "Weekly UTC time window for maintenance."
  type        = string
  default     = "sun:04:30-sun:05:30"
}

variable "db_skip_final_snapshot" {
  description = "true = no final snapshot when the database is destroyed (convenient for coursework). Set false for anything you care about."
  type        = bool
  default     = true
}

variable "db_deletion_protection" {
  description = "Block deletion of the database until this is switched off."
  type        = bool
  default     = false
}

variable "db_secret_recovery_window_in_days" {
  description = "Days Secrets Manager keeps a deleted secret before removal (0 = delete immediately, or 7-30). 0 avoids name clashes if you destroy and re-create."
  type        = number
  default     = 0

  validation {
    condition     = var.db_secret_recovery_window_in_days == 0 || (var.db_secret_recovery_window_in_days >= 7 && var.db_secret_recovery_window_in_days <= 30)
    error_message = "db_secret_recovery_window_in_days must be 0 or between 7 and 30."
  }
}

# -----------------------------------------------------------------------------
# Shared storage (EFS)
# -----------------------------------------------------------------------------
variable "efs_performance_mode" {
  description = "EFS performance mode: generalPurpose (right for Drupal) or maxIO."
  type        = string
  default     = "generalPurpose"
}

variable "efs_throughput_mode" {
  description = "EFS throughput mode: bursting or elastic."
  type        = string
  default     = "bursting"
}

variable "efs_transition_to_ia" {
  description = "Move files not accessed for this long to the cheaper Infrequent Access class (for example AFTER_30_DAYS). Set to null to disable."
  type        = string
  default     = "AFTER_30_DAYS"
}

# -----------------------------------------------------------------------------
# Locals shared by every file
# -----------------------------------------------------------------------------
locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}