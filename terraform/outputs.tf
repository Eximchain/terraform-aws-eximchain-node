output "eximchain_node_dns" {
  value = "${aws_instance.eximchain_node.public_dns}"
}
