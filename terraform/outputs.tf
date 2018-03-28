output "eximchain_node_dns" {
  value = "${aws_instance.eximchain_node.public_dns}"
}

output "eximchain_node_rpc_port" {
  # TODO: Make this not hard-coded
  value = "22000"
}
