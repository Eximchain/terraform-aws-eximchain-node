resource "aws_security_group_rule" "eximchain_node_rpc_external" {
  security_group_id = "${var.node_security_group}"
  type              = "ingress"

  from_port = "${var.rpc_port}"
  to_port   = "${var.rpc_port}"
  protocol  = "tcp"

  source_security_group_id = "${var.rpc_security_group}"
}
