# ---------------------------------------------------------------------------------------------------------------------
# PROVIDERS
# ---------------------------------------------------------------------------------------------------------------------
provider "aws" {
  version = "~> 1.5"

  region  = "${var.aws_region}"
}

provider "template" {
  version = "~> 1.0"
}

provider "tls" {
  version = "~> 1.1"
}

provider "local" {
  version = "~> 1.1"
}

# ---------------------------------------------------------------------------------------------------------------------
# CERTIFICATES FOR VAULT
# ---------------------------------------------------------------------------------------------------------------------
module "cert_tool" {
  source = "../cert-tool"

  ca_public_key_file_path = "${path.module}/certs/ca.crt.pem"
  public_key_file_path    = "${path.module}/certs/vault.crt.pem"
  private_key_file_path   = "${path.module}/certs/vault.key.pem"
  owner                   = "${var.cert_owner}"
  organization_name       = "${var.cert_org_name}"
  ca_common_name          = "eximchain-node-vault cert authority"
  common_name             = "eximchain-node cert network"
  dns_names               = ["localhost"]
  ip_addresses            = ["127.0.0.1"]
  validity_period_hours   = 8760
}

# ---------------------------------------------------------------------------------------------------------------------
# NETWORKING
# ---------------------------------------------------------------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "eximchain_node" {
  # At least two for the load balancer, otherwise one per node up to the number of AZs
  count = "${max(2, min(var.node_count, length(var.availability_zones) == 0 ? length(data.aws_availability_zones.available.names) : length(var.availability_zones)))}"

  vpc_id                  = "${var.aws_vpc}"
  availability_zone       = "${length(var.availability_zones) != 0 ? element(concat(var.availability_zones, list("")), count.index) : element(data.aws_availability_zones.available.names, count.index)}"
  cidr_block              = "${cidrsubnet(cidrsubnet(var.base_subnet_cidr, 2, 0), 4, count.index)}"
  map_public_ip_on_launch = true
}

# ---------------------------------------------------------------------------------------------------------------------
# PUBLIC KEY FILE IF USED
# ---------------------------------------------------------------------------------------------------------------------
data "local_file" "public_key" {
  count = "${var.public_key == "" ? 1 : 0}"

  filename = "${var.public_key_path}"
}

# ---------------------------------------------------------------------------------------------------------------------
# KEY PAIR
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_key_pair" "auth" {
  key_name_prefix = "eximchain-node-net-${var.network_id}-"
  public_key      = "${var.public_key == "" ? join("", data.local_file.public_key.*.content) : var.public_key}"
}

# ---------------------------------------------------------------------------------------------------------------------
# S3 BACKEND
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_s3_bucket" "vault_storage" {
  bucket_prefix = "eximchain-node-"
  force_destroy = "${var.force_destroy_s3_bucket}"
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM ROLE
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_role" "eximchain_node" {
  name_prefix = "eximchain-node-net-${var.network_id}-"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Action": "sts:AssumeRole",
    "Principal": {
      "Service": "ec2.amazonaws.com"
    },
    "Effect": "Allow",
    "Sid": ""
  }]
}
EOF
}

resource "aws_iam_policy" "allow_aws_auth" {
  name_prefix = "eximchain-aws-auth-net-${var.network_id}-"
  description = "Allow authentication to vault by AWS mechanisms"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ec2:DescribeInstances",
      "iam:GetInstanceProfile",
      "iam:GetUser",
      "iam:GetRole"
    ],
    "Resource": "*"
  }]
}
EOF
}

resource "aws_iam_policy" "allow_s3_bucket" {
  name_prefix = "eximchain-s3-bucket-net-${var.network_id}-"
  description = "Allow authentication to vault by AWS mechanisms"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:*"],
    "Resource": [
      "${aws_s3_bucket.vault_storage.arn}",
      "${aws_s3_bucket.vault_storage.arn}/*"
    ]
  }]
}
EOF
}

resource "aws_iam_role_policy_attachment" "allow_aws_auth" {
  role       = "${aws_iam_role.eximchain_node.name}"
  policy_arn = "${aws_iam_policy.allow_aws_auth.arn}"
}

resource "aws_iam_role_policy_attachment" "allow_s3_bucket" {
  role       = "${aws_iam_role.eximchain_node.name}"
  policy_arn = "${aws_iam_policy.allow_s3_bucket.arn}"
}

module "consul_iam_policies_servers" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-iam-policies?ref=v0.1.0"

  iam_role_id = "${aws_iam_role.eximchain_node.name}"
}

resource "aws_iam_instance_profile" "eximchain_node" {
  name = "${aws_iam_role.eximchain_node.name}"
  role = "${aws_iam_role.eximchain_node.name}"
}

# ---------------------------------------------------------------------------------------------------------------------
# SECURITY GROUP
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_security_group" "eximchain_node" {
  name        = "eximchain_node"
  description = "Used for eximchain node"
  vpc_id      = "${var.aws_vpc}"
}

resource "aws_security_group_rule" "eximchain_node_ssh" {
  security_group_id = "${aws_security_group.eximchain_node.id}"
  type              = "ingress"

  from_port = 22
  to_port   = 22
  protocol  = "tcp"

  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "eximchain_node_constellation" {
  security_group_id = "${aws_security_group.eximchain_node.id}"
  type              = "ingress"

  from_port = 9000
  to_port   = 9000
  protocol  = "tcp"

  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "eximchain_node_quorum" {
  security_group_id = "${aws_security_group.eximchain_node.id}"
  type              = "ingress"

  from_port = 21000
  to_port   = 21000
  protocol  = "tcp"

  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "quorum_udp" {
  security_group_id = "${aws_security_group.eximchain_node.id}"
  type              = "ingress"

  from_port = 21000
  to_port   = 21000
  protocol  = "udp"

  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "eximchain_node_rpc_self" {
  security_group_id = "${aws_security_group.eximchain_node.id}"
  type              = "ingress"

  from_port = 22000
  to_port   = 22000
  protocol  = "tcp"

  self = true
}

resource "aws_security_group_rule" "eximchain_node_rpc_cidrs" {
  count = "${length(var.rpc_cidrs) == 0 ? 0 : 1}"

  security_group_id = "${aws_security_group.eximchain_node.id}"
  type              = "ingress"

  from_port = 22000
  to_port   = 22000
  protocol  = "tcp"

  cidr_blocks = "${var.rpc_cidrs}"
}

resource "aws_security_group_rule" "eximchain_node_rpc_security_groups" {
  count = "${var.num_rpc_security_groups}"

  security_group_id = "${aws_security_group.eximchain_node.id}"
  type              = "ingress"

  from_port = 22000
  to_port   = 22000
  protocol  = "tcp"

  source_security_group_id = "${element(var.rpc_security_groups, count.index)}"
}

resource "aws_security_group_rule" "eximchain_node_rpc_lb" {
  count = "${var.create_load_balancer ? 1 : 0}"

  security_group_id = "${aws_security_group.eximchain_node.id}"
  type              = "ingress"

  from_port = 22000
  to_port   = 22000
  protocol  = "tcp"

  source_security_group_id = "${aws_security_group.eximchain_load_balancer.id}"
}

resource "aws_security_group_rule" "eximchain_node_egress" {
  security_group_id = "${aws_security_group.eximchain_node.id}"
  type              = "egress"

  from_port = 0
  to_port   = 0
  protocol  = "-1"

  cidr_blocks = ["0.0.0.0/0"]
}

# ---------------------------------------------------------------------------------------------------------------------
# EXIMCHAIN NODE
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_autoscaling_group" "eximchain_node" {
  count = "${var.node_count}"

  name_prefix = "eximchain-node-${count.index}-net-${var.network_id}-"

  launch_configuration = "${element(aws_launch_configuration.eximchain_node.*.name, count.index)}"

  target_group_arns = ["${element(coalescelist(aws_lb_target_group.eximchain_node_rpc.*.arn, list("")), 0)}"]

  min_size         = 1
  max_size         = 1
  desired_capacity = 1

  health_check_grace_period = 300
  health_check_type         = "EC2"

  vpc_zone_identifier = ["${element(aws_subnet.eximchain_node.*.id, count.index)}"]
}

resource "aws_launch_configuration" "eximchain_node" {
  count = "${var.node_count}"

  name_prefix = "eximchain-node-${count.index}-net-${var.network_id}-"

  image_id      = "${var.eximchain_node_ami == "" ? data.aws_ami.eximchain_node.id : var.eximchain_node_ami}"
  instance_type = "${var.eximchain_node_instance_type}"
  user_data     = "${element(data.template_file.user_data_eximchain_node.*.rendered, count.index)}"

  key_name = "${aws_key_pair.auth.id}"

  iam_instance_profile = "${aws_iam_instance_profile.eximchain_node.name}"
  security_groups      = ["${aws_security_group.eximchain_node.id}"]

  root_block_device {
    volume_size = "${var.node_volume_size}"
  }
}

data "template_file" "user_data_eximchain_node" {
  count = "${var.node_count}"

  template = "${file("${path.module}/user-data/user-data-eximchain-node.sh")}"

  vars {
    aws_region     = "${var.aws_region}"
    network_id     = "${var.network_id}"
    s3_bucket_name = "${aws_s3_bucket.vault_storage.id}"
    iam_role_name  = "${aws_iam_role.eximchain_node.name}"

    vault_dns         = "${var.vault_dns}"
    vault_port        = "${var.vault_port}"
    vault_cert_bucket = "${var.vault_cert_bucket}"

    vault_ca_public_key = "${module.cert_tool.ca_public_key}"
    vault_public_key    = "${module.cert_tool.public_key}"
    vault_private_key   = "${module.cert_tool.private_key}"

    consul_cluster_tag_key   = "${var.consul_cluster_tag_key}"
    consul_cluster_tag_value = "${var.consul_cluster_tag_value}"

    node_index = "${count.index}"
  }
}

data "aws_ami" "eximchain_node" {
  most_recent = true
  owners      = ["037794263736"]

  filter {
    name   = "name"
    values = ["eximchain-node-*"]
  }
}

data "aws_instance" "eximchain_node" {
  count = "${var.node_count}"

  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = ["${element(aws_autoscaling_group.eximchain_node.*.name, count.index)}"]
  }
}
