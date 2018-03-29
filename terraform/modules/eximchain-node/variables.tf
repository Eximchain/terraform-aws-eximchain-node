# ---------------------------------------------------------------------------------------------------------------------
# REQUIRED PARAMETERS
# You must provide a value for each of these parameters.
# ---------------------------------------------------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region to launch servers."
}

variable "availability_zone" {
  description = "AWS availability zone to launch the node in"
}

variable "aws_vpc" {
  description = "The VPC to place the node in"
}

variable "public_key_path" {
  description = "The path to the public key that will be used to SSH the instances in this region."
}

variable "cert_owner" {
  description = "The OS user to be made the owner of the local copy of the vault certificates. Should usually be set to the user operating the tool."
}

variable "eximchain_node_amis" {
  description = "Mapping from AWS region to AMI ID to use for transaction executor nodes in that region"
  type        = "map"
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# These parameters have reasonable defaults.
# ---------------------------------------------------------------------------------------------------------------------
variable "vault_dns" {
  description = "The dns that vault will be accessible on. Leave as default for a local vault."
  default     = "127.0.0.1"
}

variable "vault_cert_bucket" {
  description = "The name of the S3 bucket containing vault certificates. Leave empty if using a local vault."
  default     = ""
}

variable "vault_port" {
  description = "The port that vault will be accessible on."
  default     = 8200
}

variable "network_id" {
  description = "The network ID of the eximchain network to join"
  default     = 513
}

variable "node_volume_size" {
  description = "The size of the storage drive on the node"
  default     = 50
}

variable "rpc_access_security_groups" {
  description = "A list of security groups to grant RPC access to"
  default     = []
}

variable "force_destroy_s3_bucket" {
  description = "Whether or not to force destroy vault s3 bucket. Set to true for an easily destroyed test environment. DO NOT set to true for a production environment."
  default     = false
}

variable "eximchain_node_instance_type" {
  description = "The EC2 instance type to use for transaction executor nodes"
  default     = "t2.medium"
}

variable "cert_org_name" {
  description = "The organization to associate with the vault certificates."
  default     = "Example Co."
}

variable "consul_cluster_tag_key" {
  description = "consul tag key"
  default     = "eximchain-node-consul-key"
}

variable "consul_cluster_tag_value" {
  description = "consul tag value"
  default     = "auto-join"
}
