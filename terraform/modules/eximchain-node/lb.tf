# ---------------------------------------------------------------------------------------------------------------------
# LOAD BALANCER FOR VAULT
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_lb" "eximchain_node" {
  count = "${var.create_load_balancer ? 1 : 0}"

  internal = "${var.use_internal_load_balancer}"

  subnets         = ["${aws_subnet.eximchain_node.*.id}"]
  security_groups = ["${aws_security_group.eximchain_load_balancer.id}"]
}

resource "aws_lb_target_group" "eximchain_node_rpc" {
  count = "${var.create_load_balancer ? 1 : 0}"

  name_prefix = "exim-"
  port        = 22000
  protocol    = "HTTP"
  vpc_id      = "${var.aws_vpc}"
}

resource "aws_lb_listener" "eximchain_node_rpc" {
  count = "${var.create_load_balancer ? 1 : 0}"

  load_balancer_arn = "${aws_lb.eximchain_node.arn}"
  port              = 22000
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_lb_target_group.eximchain_node_rpc.arn}"
    type             = "forward"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# LOAD BALANCER SECURITY GROUP
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_security_group" "eximchain_load_balancer" {
  count = "${var.create_load_balancer ? 1 : 0}"

  name_prefix = "eximchain-lb-"
  description = "Security group for the eximchain load balancer"
  vpc_id      = "${var.aws_vpc}"

  # aws_launch_configuration.launch_configuration in this module sets create_before_destroy to true, which means
  # everything it depends on, including this resource, must set it as well, or you'll get cyclic dependency errors
  # when you try to do a terraform destroy.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "eximchain_load_balancer_rpc_self" {
  count = "${var.create_load_balancer ? 1 : 0}"

  security_group_id = "${aws_security_group.eximchain_load_balancer.id}"
  type              = "ingress"

  from_port = 22000
  to_port   = 22000
  protocol  = "tcp"

  self = true
}

resource "aws_security_group_rule" "eximchain_load_balancer_rpc_cidrs" {
  count = "${var.create_load_balancer ? length(var.rpc_cidrs) == 0 ? 0 : 1 : 0}"

  security_group_id = "${aws_security_group.eximchain_load_balancer.id}"
  type              = "ingress"

  from_port = 22000
  to_port   = 22000
  protocol  = "tcp"

  cidr_blocks = "${var.rpc_cidrs}"
}

resource "aws_security_group_rule" "eximchain_load_balancer_rpc_security_groups" {
  count = "${var.create_load_balancer ? var.num_rpc_security_groups : 0}"

  security_group_id = "${aws_security_group.eximchain_load_balancer.id}"
  type              = "ingress"

  from_port = 22000
  to_port   = 22000
  protocol  = "tcp"

  source_security_group_id = "${element(var.rpc_security_groups, count.index)}"
}

resource "aws_security_group_rule" "eximchain_lb_egress" {
  count = "${var.create_load_balancer ? 1 : 0}"

  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = "${aws_security_group.eximchain_load_balancer.id}"
}
