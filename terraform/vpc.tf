# vpc.tf
# Three-tier network across the chosen Availability Zones:
#   public       -> ALB + NAT Gateways      (route to Internet Gateway)
#   private app  -> Drupal EC2 instances    (route to NAT Gateway)
#   private db   -> RDS                     (NO internet route at all)

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs               = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  nat_gateway_count = var.nat_gateway_per_az ? var.az_count : 1

  # /24 subnets carved from the VPC CIDR. The offsets (0, 10, 20) keep the three
  # tiers in separate, non-overlapping ranges, e.g. for 10.0.0.0/16:
  #   public      10.0.0.0/24,  10.0.1.0/24
  #   private app 10.0.10.0/24, 10.0.11.0/24
  #   private db  10.0.20.0/24, 10.0.21.0/24
  public_subnet_cidrs      = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_app_subnet_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 10)]
  private_db_subnet_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 20)]
}

# -----------------------------------------------------------------------------
# VPC and Internet Gateway
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # required for EFS and RDS DNS names
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# -----------------------------------------------------------------------------
# Subnets
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false # nothing launched here needs an auto-assigned public IP

  tags = {
    Name = "${local.name_prefix}-public-${local.azs[count.index]}"
    Tier = "public"
  }
}

resource "aws_subnet" "private_app" {
  count = var.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.private_app_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-app-${local.azs[count.index]}"
    Tier = "private-app"
  }
}

resource "aws_subnet" "private_db" {
  count = var.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.private_db_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-db-${local.azs[count.index]}"
    Tier = "private-db"
  }
}

# -----------------------------------------------------------------------------
# NAT Gateways (outbound internet for the private app subnets)
# One per AZ when nat_gateway_per_az = true, otherwise a single shared one.
# -----------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id # NAT lives in a PUBLIC subnet

  tags = {
    Name = "${local.name_prefix}-nat-${local.azs[count.index]}"
  }

  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# Public route table: default route to the Internet Gateway
# -----------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = var.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# Private app route tables: one per AZ, default route to a NAT Gateway
# (its own AZ's NAT when per-AZ is on, otherwise the single shared NAT)
# -----------------------------------------------------------------------------
resource "aws_route_table" "private_app" {
  count = var.az_count

  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-app-rt-${local.azs[count.index]}"
  }
}

resource "aws_route" "private_app_nat" {
  count = var.az_count

  route_table_id         = aws_route_table.private_app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[var.nat_gateway_per_az ? count.index : 0].id
}

resource "aws_route_table_association" "private_app" {
  count = var.az_count

  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app[count.index].id
}

# -----------------------------------------------------------------------------
# Private DB route table: intentionally has NO default route.
# Only the automatic local VPC route exists, so the database tier cannot reach
# (or be reached from) the internet.
# -----------------------------------------------------------------------------
resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-db-rt"
  }
}

resource "aws_route_table_association" "private_db" {
  count = var.az_count

  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db.id
}