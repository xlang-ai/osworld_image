variable "build_id" {
  type        = string
  default     = ""
  description = "Optional build identifier. Defaults to a timestamp when empty."
}

variable "desktop_user" {
  type        = string
  default     = "user"
  description = "Existing OSWorld desktop user to configure. The playbook fails if this user is absent."
}

variable "ssh_username" {
  type        = string
  default     = "user"
  description = "SSH username for local VM builders. Override if the base image uses a different existing OSWorld user."
}

variable "ssh_password" {
  type        = string
  default     = "password"
  sensitive   = true
  description = "Initial SSH password for local VM builders. The OSWorld local VM bases use the public default password. QEMU and VMware artifacts reset the user password to the public OSWorld password during provisioning."
}

variable "ssh_timeout" {
  type    = string
  default = "45m"
}

variable "windows_winrm_username" {
  type        = string
  default     = "Administrator"
  description = "WinRM username for the Windows OSWorld qcow2 base image."
}

variable "windows_winrm_password" {
  type        = string
  default     = "osworld-public-evaluation"
  sensitive   = true
  description = "WinRM password set by the Windows boot command before provisioning. Keep this aligned with windows_final_password unless intentionally testing a password rotation."
}

variable "windows_winrm_timeout" {
  type    = string
  default = "60m"
}

variable "windows_final_password" {
  type        = string
  default     = "osworld-public-evaluation"
  sensitive   = true
  description = "Final password for the Windows OSWorld desktop user and AutoAdminLogon."
}

variable "headless" {
  type    = bool
  default = true
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for the AMI build."
}

variable "aws_source_ami" {
  type        = string
  default     = "ami-0d23263edb96951d8"
  description = "Known-good OSWorld base AMI. Do not replace with an Ubuntu owner/filter."
}

variable "aws_instance_type" {
  type    = string
  default = "g5.xlarge"
}

variable "aws_ssh_username" {
  type        = string
  default     = "user"
  description = "SSH username for the AWS source AMI."
}

variable "aws_ssh_password" {
  type        = string
  default     = "osworld-public-evaluation"
  sensitive   = true
  description = "SSH password for the AWS source AMI. The OSWorld AWS base uses this public default password."
}

variable "aws_subnet_id" {
  type        = string
  default     = ""
  description = "Optional existing subnet. Empty lets the amazon-ebs builder use account defaults."
}

variable "aws_security_group_id" {
  type        = string
  default     = ""
  description = "Optional existing security group. Empty lets the amazon-ebs builder create a temporary group."
}

variable "aws_associate_public_ip" {
  type    = bool
  default = true
}

variable "aws_ami_name" {
  type        = string
  default     = ""
  description = "Optional exact AMI name. Defaults to aws_ami_name_prefix-build_id when empty."
}

variable "aws_ami_name_prefix" {
  type    = string
  default = "osworld-delta"
}

variable "qemu_source_qcow2" {
  type        = string
  default     = "downloads/qemu/Ubuntu.qcow2"
  description = "Path to the unzipped OSWorld qcow2 base image."
}

variable "qemu_source_qcow2_checksum" {
  type        = string
  default     = "none"
  description = "Checksum for qemu_source_qcow2, for example sha256:<hex>. The download script writes this into an ignored var file."
}

variable "qemu_output_directory" {
  type    = string
  default = "build/qemu-osworld"
}

variable "qemu_vm_name" {
  type    = string
  default = "osworld-v2-ubuntu-x86.qcow2"
}

variable "windows_source_qcow2" {
  type        = string
  default     = "downloads/windows/Windows-10-x64.qcow2"
  description = "Path to the unzipped Windows OSWorld qcow2 base image."
}

variable "windows_source_qcow2_checksum" {
  type        = string
  default     = "none"
  description = "Checksum for windows_source_qcow2, for example sha256:<hex>. The download script writes this into an ignored var file."
}

variable "windows_output_directory" {
  type    = string
  default = "build/windows-osworld"
}

variable "windows_vm_name" {
  type    = string
  default = "osworld-v2-win-x86.qcow2"
}

variable "windows_efi_firmware" {
  type        = string
  default     = "/usr/share/qemu/OVMF.fd"
  description = "Monolithic OVMF firmware used to boot the Windows qcow2 base image without a separate efivars artifact."
}

variable "qemu_accelerator" {
  type    = string
  default = "kvm"
}

variable "vmware_source_vmx" {
  type        = string
  default     = "downloads/vmware/Ubuntu.vmx"
  description = "Path to the unzipped OSWorld VMware .vmx base."
}

variable "vmware_output_directory" {
  type    = string
  default = "build/vmware-osworld"
}

variable "vmware_vm_name" {
  type    = string
  default = "osworld-delta"
}

locals {
  effective_build_id = var.build_id != "" ? var.build_id : formatdate("YYYYMMDD-hhmmss", timestamp())
  ansible_common_args = [
    "--extra-vars", "osworld_user=${var.desktop_user}",
  ]
}
