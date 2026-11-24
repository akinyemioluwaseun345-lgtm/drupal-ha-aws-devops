# storage.tf
# Shared, encrypted file storage (EFS) so every application server sees the
# same Drupal files (uploads, public files). Ansible mounts it later.

resource "aws_efs_file_system" "drupal" {
  creation_token   = "${local.name_prefix}-efs"
  encrypted        = true
  performance_mode = var.efs_performance_mode
  throughput_mode  = var.efs_throughput_mode

  dynamic "lifecycle_policy" {
    for_each = var.efs_transition_to_ia == null ? [] : [var.efs_transition_to_ia]

    content {
      transition_to_ia = lifecycle_policy.value
    }
  }

  tags = {
    Name = "${local.name_prefix}-efs"
  }
}

# One mount target per AZ, inside the private app subnets, so each server
# mounts storage through a network interface in its own AZ.
resource "aws_efs_mount_target" "app" {
  count = var.az_count

  file_system_id  = aws_efs_file_system.drupal.id
  subnet_id       = aws_subnet.private_app[count.index].id
  security_groups = [aws_security_group.efs.id]
}