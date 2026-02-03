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

source "amazon-ebs" "amazon_linux" {
  ami_name      = "schedemy-al2023-{{timestamp}}"
  ami_description = "Schedemy Spring Boot immutable image"
  instance_type = "t3.small"
  region        = var.aws_region
	
  tags = {
    App = "schedemy"
    BuiltBy = "packer"}

 
  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["137112412989"] 
  }
  ssh_username = "ec2-user"
}

build {
  name    = "schedemy-builder"
  sources = ["source.amazon-ebs.ubuntu"]

  # Run Ansible to install software
  provisioner "ansible" {
    playbook_file = "./.ansible/playbooks/playbook0.yml"
	user		  = "ec2-user"

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
