data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = var.name }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = var.name }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = { Name = "${var.name}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "minecraft" {
  name        = var.name
  description = "Minecraft server"
  vpc_id      = aws_vpc.this.id

  tags = { Name = var.name }
}

resource "aws_vpc_security_group_ingress_rule" "minecraft" {
  for_each = toset(var.allowed_cidrs)

  security_group_id = aws_security_group.minecraft.id
  description       = "Minecraft Java Edition"
  ip_protocol       = "tcp"
  from_port         = 25565
  to_port           = 25565
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.minecraft.id
  description       = "All outbound (package installs, Mojang downloads, SSM)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
