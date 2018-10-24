# ---------------------------------------------------------------------------------------------------------------------
# PROVIDERS
# ---------------------------------------------------------------------------------------------------------------------
provider "aws" {
  version = "~> 1.5"

  region  = "${var.aws_region}"
}

# ---------------------------------------------------------------------------------------------------------------------
# NETWORKING
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_vpc" "eximchain_node" {
  cidr_block           = "${var.vpc_cidr}"
  enable_dns_hostnames = true
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "eximchain_node" {
  vpc_id = "${aws_vpc.eximchain_node.id}"
}

# Grant the VPC internet access on its main route table
resource "aws_route" "eximchain_node" {
  route_table_id         = "${aws_vpc.eximchain_node.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.eximchain_node.id}"
}

# ---------------------------------------------------------------------------------------------------------------------
# EXIMCHAIN NODE
# ---------------------------------------------------------------------------------------------------------------------
module "eximchain_node" {
  source = "modules/eximchain-node"

  network_id                   = "${var.network_id}"
  public_key_path              = "${var.public_key_path}"
  public_key                   = "${var.public_key}"
  aws_region                   = "${var.aws_region}"
  availability_zone            = "${var.availability_zone}"
  lb_extra_az                  = "${var.lb_extra_az}"
  cert_owner                   = "${var.cert_owner}"
  node_count                   = "${var.node_count}"
  node_volume_size             = "${var.node_volume_size}"
  force_destroy_s3_bucket      = "${var.force_destroy_s3_bucket}"
  eximchain_node_instance_type = "${var.eximchain_node_instance_type}"

  vault_dns         = "${var.vault_dns}"
  vault_cert_bucket = "${var.vault_cert_bucket}"
  vault_port        = "${var.vault_port}"

  cert_org_name            = "${var.cert_org_name}"
  consul_cluster_tag_key   = "${var.consul_cluster_tag_key}"
  consul_cluster_tag_value = "${var.consul_cluster_tag_value}"

  rpc_cidrs           = "${var.rpc_cidrs}"
  rpc_security_groups = "${var.rpc_security_groups}"

  eximchain_node_ami = "${var.eximchain_node_ami}"

  aws_vpc = "${aws_vpc.eximchain_node.id}"

  base_subnet_cidr = "${var.vpc_cidr}"
}
