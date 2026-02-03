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
  ami_description = "Schedemy Spring Boot immutable image"
  instance_type = "t3.small"
  region        = var.aws_region
	
  tags = {
    App = "schedemy"
    BuiltBy = "packer"}

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
    playbook_file = "./.ansible/playbooks/playbook0.yml"
	user		  = "ubuntu"

	extra_arguments = [
      "--extra-vars", "project_root=${path.cwd}"
  ]
  }
  # THIS ADDS THE JSON MANIFEST
  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
