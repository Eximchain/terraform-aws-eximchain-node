variable "node_security_group" {
  description = "Security group running the node to grant RPC access to"
}

variable "rpc_security_group" {
  description = "Security group to grant RPC access to"
}

variable "using_lb" {
  description = "Whether a load balancer is being used"
  default     = false
}

variable "lb_security_group" {
  description = "Security group running the load balancer to grant RPC access to"
  default     = ""
}

variable "rpc_port" {
  description = "The port the RPC server is available on"
  default     = 22000
}
