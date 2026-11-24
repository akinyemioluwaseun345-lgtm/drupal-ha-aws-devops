# ec2.tf
# Application servers: Amazon Linux 2023 instances created from a Launch
# Template and managed by an Auto Scaling Group across the private app subnets.
# NO user data on purpose: Ansible installs and configures Drupal later.

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_launch_template" "app" {
  name_prefix            = "${local.name_prefix}-app-lt-"
  description            = "Drupal application server (Amazon Linux 2023)"
  image_id               = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  update_default_version = true

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  # No public IP, and only the app security group.
  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    security_groups             = [aws_security_group.app.id]
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.root_volume_size_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # IMDSv2 only (blocks a common credential-theft technique).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Provider default_tags do not reach launch template tag specifications,
  # so the tags for instances and volumes are set here explicitly.
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-app"
      Role = "drupal-app"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-app-root"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${local.name_prefix}-app-asg"
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity
  vpc_zone_identifier       = aws_subnet.private_app[*].id # one subnet per AZ
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = var.asg_health_check_type
  health_check_grace_period = var.asg_health_check_grace_period

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  # Tags on the Auto Scaling Group itself (instance tags come from the template).
  dynamic "tag" {
    for_each = merge(local.common_tags, { Name = "${local.name_prefix}-app-asg" })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }

  # Instances need the NAT route (for SSM) and the listener in place first.
  depends_on = [
    aws_route.private_app_nat,
    aws_lb_listener.http
  ]

  lifecycle {
    precondition {
      condition     = var.asg_min_size <= var.asg_desired_capacity && var.asg_desired_capacity <= var.asg_max_size
      error_message = "Capacity must satisfy asg_min_size <= asg_desired_capacity <= asg_max_size."
    }
  }
}