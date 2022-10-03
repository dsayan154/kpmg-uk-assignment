locals {
  config = yamldecode(file("${path.module}/config.yaml"))
  vpc_cidr = local.config.vpc.cidr
  subnet_cidrs = local.config.subnetCidrs
  additional_default_tags = {
    "component" = "layer-1"
  }
  public_subnet_cidrs = local.subnet_cidrs.public
  app_subnet_cidrs = local.subnet_cidrs.app
  data_subnet_cidrs = local.subnet_cidrs.data
}

resource "aws_vpc" "wp_vpc" {
  cidr_block = local.vpc_cidr
  tags = merge(
    local.additional_default_tags,
    {
      "Name" = "wp-main"
    },
  )
}

resource "aws_subnet" "wp_public_subnets" {
  for_each          = local.public_subnet_cidrs
  vpc_id            = aws_vpc.wp_vpc.id
  availability_zone = each.key
  cidr_block        = each.value
  tags = merge(
    local.additional_default_tags,
    {
      "Name"      = format("%s-%s", "public",element(split("-", each.key), 2))
      "component" = "layer-1"
      "topology"   = "public"
    },
  )
}

resource "aws_subnet" "wp_app_subnets" {
  for_each          = local.app_subnet_cidrs
  vpc_id            = aws_vpc.wp_vpc.id
  availability_zone = each.key
  cidr_block        = each.value
  tags = merge(
    local.additional_default_tags,
    {
      "Name"      = format("%s-%s", "app",element(split("-", each.key), 2))
      "component" = "layer-1"
      "topology"   = "private"
    },
  )
}

resource "aws_subnet" "wp_data_subnets" {
  for_each          = local.data_subnet_cidrs
  vpc_id            = aws_vpc.wp_vpc.id
  availability_zone = each.key
  cidr_block        = each.value
  tags = merge(
    local.additional_default_tags,
    {
      "Name"      = format("%s-%s", "data",element(split("-", each.key), 2))
      "component" = "layer-1"
      "topology"   = "private"
    },
  )
}

resource "aws_internet_gateway" "wp_igw" {
  vpc_id = aws_vpc.wp_vpc.id
  tags = merge(
    local.additional_default_tags,
    {
        "Name" = "wp-main"
    }
  )
}

resource "aws_eip" "ngw_eips" {
  count = length(local.public_subnet_cidrs)
    depends_on = [
    aws_internet_gateway.wp_igw
  ]
  tags = merge(
    local.additional_default_tags,
    {
      "Name" = format("%s-%s", "wp-ngw-eip", count.index)
    },
  )
}

resource "aws_nat_gateway" "wp_ngws" {
  count = length(aws_subnet.wp_public_subnets)
  allocation_id = aws_eip.ngw_eips[count.index].id
  subnet_id = aws_subnet.wp_public_subnets[keys(aws_subnet.wp_public_subnets)[count.index]].id
  tags = merge(
    local.additional_default_tags,
    {
      "Name" = format("%s-%s", "wp-ngw", count.index)
    },
  )
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.wp_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wp_igw.id
  }
  tags = merge(
    local.additional_default_tags,
    {
      "Name" = "wp-public-rt"
    },
  )
#   depends_on = [
#     aws_internet_gateway.wp_igw
#   ]
}

resource "aws_route_table_association" "public_rt_subnet_associations" {
  for_each = aws_subnet.wp_public_subnets
  subnet_id = each.value.id
  route_table_id = aws_route_table.public_rt.id
}

locals {
  public_subnet_az_mappings = {
    for subnet in aws_subnet.wp_public_subnets :
        subnet.id => subnet.availability_zone
  }
  az_ngw_mappings = {
    for ngw in aws_nat_gateway.wp_ngws :
      lookup(local.public_subnet_az_mappings, ngw.subnet_id, "") => ngw.id
  }
}

resource "aws_route_table" "private_app_rts" {
  for_each = aws_subnet.wp_app_subnets
  vpc_id = aws_vpc.wp_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = lookup(local.az_ngw_mappings, each.value.availability_zone, "")
  }
  tags = merge(
    local.additional_default_tags,
    {
      "Name" = format("%s-%s","wp-private-app-rt",element(split("-",each.value.availability_zone), 2))
    },
  )
}


resource "aws_route_table" "private_data_rts" {
  for_each = aws_subnet.wp_data_subnets
  vpc_id = aws_vpc.wp_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = lookup(local.az_ngw_mappings, each.value.availability_zone, "")
  }
  tags = merge(
    local.additional_default_tags,
    {
      "Name" = format("%s-%s","wp-private-data-rt",element(split("-",each.value.availability_zone), 2))
    },
  )
}

resource "aws_route_table_association" "private_app_rt_sa" {
  for_each = aws_subnet.wp_app_subnets
  subnet_id = each.value.id
  route_table_id = aws_route_table.private_app_rts[each.value.availability_zone].id
}

resource "aws_route_table_association" "private_data_rt_sa" {
  for_each = aws_subnet.wp_data_subnets
  subnet_id = each.value.id
  route_table_id = aws_route_table.private_data_rts[each.value.availability_zone].id
}