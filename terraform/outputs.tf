output "eximchain_node_dns" {
  value = "${module.eximchain_node.eximchain_node_dns}"
}

output "eximchain_lb_zone_id" {
  value = "${module.eximchain_node.eximchain_lb_zone_id}"
}

output "eximchain_node_ssh_dns" {
  value = "${module.eximchain_node.eximchain_node_ssh_dns}"
}

output "eximchain_node_rpc_port" {
  value = "${module.eximchain_node.eximchain_node_rpc_port}"
}

output "eximchain_node_iam_role" {
  value = "${module.eximchain_node.eximchain_node_iam_role}"
}
