variable "aws_region" {
  default = "us-east-1"
}
variable "jar_s3_bucket" {
  default = "schedemy-bucket"
}
variable "jar_s3_key" {
  default = "schedemy/schedemy-commitsha.jar
}
variable "app_version" {}

source "amazon-ebs" "app" {
  region              = var.aws_region
  instance_type       = "t3.small"
  ssh_username        = "deploy"
  ami_name            = "schedemy-${var.app_version}"
  ami_description     = "Spring Boot AMI built from commit ${var.app_version}"
  iam_instance_profile = "PackerEC2Role"

  source_ami_filter {
    filters = {
      name                = "al2023-ami-*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["amazon"]
    most_recent = true
  }
}

build {
  sources = ["source.amazon-ebs.app"]

  provisioner "ansible" {
    playbook_file = "ansible/playbook.yml"
    extra_arguments = [
      "--extra-vars",
      "jar_s3_bucket=${var.jar_s3_bucket} jar_s3_key=${var.jar_s3_key}"
    ]
  }

  post-processor "manifest" {
    output = "manifest.json"
  }
}

