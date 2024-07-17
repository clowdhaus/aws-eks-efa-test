data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

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

  availability_zone = "us-east-1-atl-2a"
  cidr_block        = each.value.cidr_block
  vpc_id            = module.vpc.vpc_id

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
  route_table_id = element(module.vpc.private_route_table_ids, 0)
}
