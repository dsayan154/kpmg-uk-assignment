resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "192.168.0.0/24"
  tags = {
    "Name"      = "wordpress-main"
    "component" = "layer-1"
  }
}