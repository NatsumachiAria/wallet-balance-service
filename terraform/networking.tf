# =====================================================================
# NETWORKING — VPC, subnets, routing, NAT, S3 endpoint
#
# Public subnets exist to host the NAT gateway and to satisfy the
# public/private split the brief asks for. Nothing else lives there: the
# load balancer is internal, so every component that runs code or holds
# data sits in a private subnet with no route to an internet gateway.
# =====================================================================

resource "aws_vpc" "main" {
  cidr_block         = var.vpc_cidr
  enable_dns_support = true

  # Required for the RDS endpoint to resolve to its private address.
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

# ---------- Subnets ----------
resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = { Name = "${var.name_prefix}-public-${count.index + 1}" }
}

# ALB, ECS tasks and RDS all live here.
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = { Name = "${var.name_prefix}-private-${count.index + 1}" }
}

# ---------- Internet egress ----------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.name_prefix}-igw" }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "${var.name_prefix}-nat-eip" }
}

# One NAT gateway rather than one per availability zone. This is the
# single point of failure in the network and a deliberate cost decision
# inside the time box, recorded as a trade-off in the README.
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.main]

  tags = { Name = "${var.name_prefix}-nat" }
}

# ---------- Routing ----------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.name_prefix}-public-rtb" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# All private subnets share one route table because there is one NAT.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "${var.name_prefix}-private-rtb" }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ---------- S3 gateway endpoint ----------
# ECR stores image layers in S3. Without this endpoint every image pull
# would be metered NAT traffic. Gateway endpoints are free; interface
# endpoints for the other AWS services are a documented TODO.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${var.name_prefix}-s3-endpoint" }
}
