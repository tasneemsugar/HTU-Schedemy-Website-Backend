packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1" 
}

source "amazon-ebs" "ubuntu" {
  ami_name      = "schedemy-app-{{timestamp}}"
  instance_type = "t3.small"
  region        = var.aws_region
  
  # Find the base Ubuntu 22.04 image to start from
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"] # Canonical (Official Ubuntu)
  }
  ssh_username = "ubuntu"
}

build {
  name    = "schedemy-builder"
  sources = ["source.amazon-ebs.ubuntu"]

  # Run Ansible to install software
  provisioner "ansible" {
    playbook_file = "./.ansible/playbook.yml"
  }
}
