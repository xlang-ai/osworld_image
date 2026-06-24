source "amazon-ebs" "osworld" {
  region      = var.aws_region
  source_ami  = var.aws_source_ami
  ami_name    = var.aws_ami_name != "" ? var.aws_ami_name : "${var.aws_ami_name_prefix}-${local.effective_build_id}"
  ami_description = "OSWorld deterministic delta from ${var.aws_source_ami}"

  instance_type = var.aws_instance_type
  ssh_username  = var.aws_ssh_username
  ssh_password  = var.aws_ssh_password != "" ? var.aws_ssh_password : null
  ssh_timeout   = var.ssh_timeout

  associate_public_ip_address = var.aws_associate_public_ip
  subnet_id                   = var.aws_subnet_id != "" ? var.aws_subnet_id : null
  security_group_id           = var.aws_security_group_id != "" ? var.aws_security_group_id : null

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_type           = "gp3"
    volume_size           = 100
    delete_on_termination = true
  }

  run_tags = {
    Project   = "osworld"
    Builder   = "packer"
    DeltaOnly = "true"
  }

  tags = {
    Project      = "osworld"
    SourceAMI    = var.aws_source_ami
    DeltaOnly    = "true"
    BuildID      = local.effective_build_id
    ManagedBy    = "packer"
  }
}

build {
  name    = "aws"
  sources = ["source.amazon-ebs.osworld"]

  provisioner "ansible" {
    playbook_file   = "${path.root}/../ansible/playbook.yml"
    use_proxy       = true
    ansible_env_vars = [
      "ANSIBLE_CONFIG=${path.root}/../ansible.cfg",
      "ANSIBLE_REMOTE_TEMP=/tmp/.ansible-osworld",
      "ANSIBLE_REMOTE_TMP=/tmp/.ansible-osworld",
      "ANSIBLE_BECOME_PASSWORD_FILE=${path.root}/../scripts/ansible-become-pass.sh",
      "OSWORLD_SUDO_PASSWORD=${var.aws_ssh_password}",
    ]
    extra_arguments = concat(local.ansible_common_args, ["--extra-vars", "target_platform=aws"])
  }
}
