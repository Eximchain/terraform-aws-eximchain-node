output "node_security_group_rule_id" {
  value = "${aws_security_group_rule.rpc_external_node.id}"
}

output "lb_security_group_rule_id" {
  value = "${element(coalescelist(aws_security_group_rule.rpc_external_lb.*.id, list("")), 0)}"
}
