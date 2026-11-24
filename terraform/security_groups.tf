# security_groups.tf
# Least-privilege firewall rules. Traffic flow:
#   Internet -> ALB (80) -> App servers (app_port) -> RDS (3306)
#                                          \-> EFS (2049)
# Rules are separate resources (aws_vpc_security_group_*_rule) so the ALB and
# app security groups can reference each other without a circular dependency.
# There is deliberately NO SSH (port 22) rule anywhere: use AWS Systems Manager.

# -----------------------------------------------------------------------------
# Load balancer
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Application Load Balancer: HTTP from the internet"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-alb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each = toset(var.alb_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTP from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward traffic to application servers only"
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}

# -----------------------------------------------------------------------------
# Application servers
# -----------------------------------------------------------------------------
resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app-sg"
  description = "Drupal application servers: web traffic from the ALB only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-app-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "Web traffic from the load balancer"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}

# Outbound is open so the instances can reach Systems Manager and OS/package
# repositories through the NAT Gateway (HTTPS), and the database/EFS inside the VPC.
# Nothing on the internet can initiate a connection to them.
resource "aws_vpc_security_group_egress_rule" "app_all_outbound" {
  security_group_id = aws_security_group.app.id
  description       = "All outbound (SSM, package updates, database, EFS)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# -----------------------------------------------------------------------------
# Database
# -----------------------------------------------------------------------------
resource "aws_security_group" "db" {
  name        = "${local.name_prefix}-db-sg"
  description = "RDS MySQL: database traffic from application servers only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-db-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "MySQL from application servers"
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = var.db_port
  to_port                      = var.db_port
  ip_protocol                  = "tcp"
}

# -----------------------------------------------------------------------------
# Shared storage (EFS)
# -----------------------------------------------------------------------------
resource "aws_security_group" "efs" {
  name        = "${local.name_prefix}-efs-sg"
  description = "EFS: NFS traffic from application servers only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-efs-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "efs_from_app" {
  security_group_id            = aws_security_group.efs.id
  description                  = "NFS from application servers"
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
}