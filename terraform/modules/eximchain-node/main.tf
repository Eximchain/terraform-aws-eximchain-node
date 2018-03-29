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
resource "aws_subnet" "eximchain_node" {
  vpc_id                  = "${var.aws_vpc}"
  availability_zone       = "${var.availability_zone}"
  cidr_block              = "10.0.${count.index + 1}.0/24"
  map_public_ip_on_launch = true
}

# ---------------------------------------------------------------------------------------------------------------------
# KEY PAIR
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_key_pair" "auth" {
  key_name   = "eximchain-node"
  public_key = "${file(var.public_key_path)}"
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
  name_prefix = "eximchain-node-"

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
  name = "eximchain-node-network-${var.network_id}"
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

resource "aws_security_group_rule" "eximchain_node_rpc" {
  security_group_id = "${aws_security_group.eximchain_node.id}"
  type              = "ingress"

  from_port = 22000
  to_port   = 22000
  protocol  = "tcp"

  cidr_blocks = ["127.0.0.1/32"]
}

resource "aws_security_group_rule" "eximchain_node_rpc_external" {
  count = "${length(var.rpc_access_security_groups)}"

  security_group_id = "${aws_security_group.eximchain_node.id}"
  type              = "ingress"

  from_port = 22000
  to_port   = 22000
  protocol  = "tcp"

  source_security_group_id = "${element(var.rpc_access_security_groups, count.index)}"
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
resource "aws_instance" "eximchain_node" {
  connection {
    # The default username for our AMI
    user = "ubuntu"

    # The connection will use the local SSH agent for authentication.
  }

  instance_type = "${var.eximchain_node_instance_type}"

  ami       = "${lookup(var.eximchain_node_amis, var.aws_region)}"
  user_data = "${data.template_file.user_data_eximchain_node.rendered}"

  key_name = "${aws_key_pair.auth.id}"

  iam_instance_profile = "${aws_iam_instance_profile.eximchain_node.name}"

  vpc_security_group_ids = ["${aws_security_group.eximchain_node.id}"]
  subnet_id              = "${aws_subnet.eximchain_node.id}"

  tags {
    Name = "eximchain-node"
  }

  root_block_device {
    volume_size = "${var.node_volume_size}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get -y update",
      "echo '${var.aws_region}' | sudo tee /opt/quorum/info/aws-region.txt",
      "echo '${module.cert_tool.ca_public_key}' | sudo tee /opt/vault/tls/ca.crt.pem",
      "echo '${module.cert_tool.public_key}' | sudo tee /opt/vault/tls/vault.crt.pem",
      "echo '${module.cert_tool.private_key}' | sudo tee /opt/vault/tls/vault.key.pem",
      "sudo chown vault /opt/vault/tls/*",
      "sudo chmod 600 /opt/vault/tls/*",
      "sudo /opt/vault/bin/update-certificate-store --cert-file-path /opt/vault/tls/ca.crt.pem",
      # This should be last because init scripts wait for this file to determine terraform is done provisioning
      "echo '${var.network_id}' | sudo tee /opt/quorum/info/network-id.txt",
    ]
  }
}

data "template_file" "user_data_eximchain_node" {
  template = "${file("${path.module}/user-data/user-data-eximchain-node.sh")}"

  vars {
    aws_region = "${var.aws_region}"
    s3_bucket_name = "${aws_s3_bucket.vault_storage.id}"

    vault_dns         = "${var.vault_dns}"
    vault_port        = "${var.vault_port}"
    vault_cert_bucket = "${var.vault_cert_bucket}"

    consul_cluster_tag_key   = "${var.consul_cluster_tag_key}"
    consul_cluster_tag_value = "${var.consul_cluster_tag_value}"
  }
}
