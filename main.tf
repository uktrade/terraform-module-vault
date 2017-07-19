data "aws_ami" "vault-ami" {
  most_recent = true
  name_regex = "ubuntu-xenial-16.04-amd64-server"
  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name = "architecture"
    values = ["x86_64"]
  }
  filter {
    name = "root-device-type"
    values = ["ebs"]
  }
}

data "template_file" "vault-cloudinit" {
  template = "${file("${path.module}/cloudinit.yml")}"

  vars {
    aws_region = "${var.vpc_conf["region"]}"
    dns_zone_id = "${var.vpc_conf["zone_id"]}"
    cluster_id = "${var.aws_conf["domain"]}"
    vault_version = "${var.vault_conf["version"]}"
    vault_port = "${var.vault_conf["port"]}"
    vault_cluster = "${var.vault_conf["id"]}.${var.aws_conf["domain"]}"
    dynamodb_table = "${aws_dynamodb_table.vault-db.id}"
  }
}

resource "aws_dynamodb_table" "vault-db" {
  name = "${var.vault_conf["id"]}.${var.aws_conf["domain"]}"
  hash_key = "${var.vault_conf["dynamodb.hash_key"]}"
  read_capacity = "${var.vault_conf["dynamodb.read_capacity"]}"
  write_capacity = "${var.vault_conf["dynamodb.write_capacity"]}"
  attribute {
    name = "key"
    type = "S"
  }
}

resource "aws_launch_configuration" "vault" {
  name_prefix = "${var.aws_conf["domain"]}-${var.vault_conf["id"]}-"
  image_id = "${data.aws_ami.vault-ami.id}"
  instance_type = "${var.aws_conf["instance_type"]}"
  key_name = "${var.aws_conf["key_name"]}"
  iam_instance_profile = "${aws_iam_instance_profile.node-profile.id}"
  security_groups = [
    "${var.vpc_conf["security_group"]}",
    "${aws_security_group.vault.id}"
  ]
  root_block_device {
    volume_type = "gp2"
    volume_size = 20
    delete_on_termination = true
  }
  user_data = "${data.template_file.vault-cloudinit.rendered}"
  associate_public_ip_address = "${lookup(var.public_ip, var.vault_conf["internal"])}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "vault" {
  name = "${var.aws_conf["domain"]}-${var.vault_conf["id"]}"
  launch_configuration = "${aws_launch_configuration.vault.name}"
  vpc_zone_identifier = ["${split(",", var.vpc_conf[lookup(var.subnet-type, var.vault_conf["internal"])])}"]
  min_size = "${var.vault_conf["capacity"]}"
  max_size = "${var.vault_conf["capacity"]}"
  desired_capacity = "${var.vault_conf["capacity"]}"
  wait_for_capacity_timeout = 0
  load_balancers = ["${aws_elb.vault.id}"]

  tag {
    key = "Name"
    value = "${var.aws_conf["domain"]}-${var.vault_conf["id"]}"
    propagate_at_launch = true
  }
  tag {
    key = "Stack"
    value = "${var.aws_conf["domain"]}"
    propagate_at_launch = true
  }
  tag {
    key = "clusterid"
    value = "${var.aws_conf["domain"]}"
    propagate_at_launch = true
  }
  tag {
    key = "svc"
    value = "vault"
    propagate_at_launch = true
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "vault" {
  name = "${var.aws_conf["domain"]}-${var.vault_conf["id"]}"
  vpc_id = "${var.vpc_conf["id"]}"

  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    self = true
  }

  ingress {
    from_port = "${var.vault_conf["port"]}"
    to_port = "${var.vault_conf["port"]}"
    protocol = "tcp"
    security_groups = ["${var.vpc_conf["security_group"]}"]
  }

  tags {
    Name = "${var.aws_conf["domain"]}-${var.vault_conf["id"]}"
    Stack = "${var.aws_conf["domain"]}"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "vault-elb" {
  name = "${var.aws_conf["domain"]}-${var.vault_conf["id"]}-elb"
  vpc_id = "${var.vpc_conf["id"]}"

  ingress {
    from_port = "${var.vault_conf["port"]}"
    to_port = "${var.vault_conf["port"]}"
    protocol = "tcp"
    security_groups = ["${var.vpc_conf["security_group"]}"]
  }

  tags {
    Name = "${var.aws_conf["domain"]}-${var.vault_conf["id"]}-elb"
    Stack = "${var.aws_conf["domain"]}"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elb" "vault" {
  name = "${element(split(".", var.aws_conf["domain"]), 0)}-${var.vault_conf["id"]}-elb"
  subnets = ["${split(",", var.vpc_conf[lookup(var.subnet-type, var.vault_conf["internal"])])}"]

  security_groups = [
    "${var.vpc_conf["security_group"]}",
    "${aws_security_group.vault-elb.id}"
  ]

  listener {
    lb_port            = "${var.vault_conf["port"]}"
    lb_protocol        = "https"
    instance_port      = "${var.vault_conf["port"]}"
    instance_protocol  = "https"
    ssl_certificate_id = "${var.vpc_conf["acm_certificate"]}"
  }

  health_check {
    healthy_threshold   = 5
    unhealthy_threshold = 2
    timeout             = 2
    target              = "TCP:${var.vault_conf["port"]}"
    interval            = 10
  }

  connection_draining = true
  cross_zone_load_balancing = true
  internal = true

  tags {
    Stack = "${var.aws_conf["domain"]}"
    Name = "${var.aws_conf["domain"]}-${var.vault_conf["id"]}-elb"
  }
}

resource "aws_route53_record" "vault" {
   zone_id = "${var.vpc_conf["zone_id"]}"
   name = "${var.vault_conf["id"]}.${var.aws_conf["domain"]}"
   type = "A"
   alias {
     name = "${aws_elb.vault.dns_name}"
     zone_id = "${aws_elb.vault.zone_id}"
     evaluate_target_health = false
   }

   lifecycle {
     create_before_destroy = true
   }
}
