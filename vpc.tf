data "aws_availability_zones" "available" {}

locals {
  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
}

################################################################################
# VPC
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = local.tags
}

################################################################################
# Local Zone Subnets
################################################################################

locals {
  lzs = {
    one = {
      cidr_block = cidrsubnet(local.vpc_cidr, 8, 51)
    }
    two = {
      cidr_block = cidrsubnet(local.vpc_cidr, 8, 52)
    }
  }
}

resource "aws_subnet" "lz" {
  for_each = local.lzs

  availability_zone_id                = "use1-atl2-az1"
  cidr_block                          = each.value.cidr_block
  private_dns_hostname_type_on_launch = true
  vpc_id                              = module.vpc.vpc_id

  tags = merge(
    {
      Name = "${local.name}-local-zone-${each.key}"
    },
    local.tags,
  )
}

resource "aws_route_table" "lz" {
  for_each = local.lzs

  vpc_id = module.vpc.vpc_id

  tags = merge(
    {
      Name = "${local.name}-local-zone-${each.key}"
    },
    local.tags,
  )
}

resource "aws_route_table_association" "lz" {
  for_each = local.lzs

  subnet_id      = aws_subnet.lz[each.key].id
  route_table_id = aws_route_table.lz[each.key].id
}

resource "aws_network_acl" "lz" {
  vpc_id     = module.vpc.vpc_id
  subnet_ids = [for sub in aws_subnet.lz : sub.id]

  tags = merge(
    {
      Name = "${local.name}-local-zone"
    },
    local.tags,
  )
}

resource "aws_network_acl_rule" "lz_ingress" {
  network_acl_id = aws_network_acl.lz.id
  egress         = false
  rule_number    = 100
  rule_action    = "allow"
  from_port      = 0
  to_port        = 0
  protocol       = "-1"
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl_rule" "lz_egress" {
  network_acl_id = aws_network_acl.lz.id
  egress         = true
  rule_number    = 100
  rule_action    = "allow"
  from_port      = 0
  to_port        = 0
  protocol       = "-1"
  cidr_block     = "0.0.0.0/0"
}
