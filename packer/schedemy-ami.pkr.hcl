/*
 * Packer Template for Schedemy Application AMI
 * 
 * What is Packer?
 * Packer is a tool that automates the creation of machine images (AMIs in AWS).
 * Think of it as a factory that builds your "golden image" automatically.
 * 
 * How it works:
 * 1. Launches a temporary EC2 instance
 * 2. Configures it (installs Java, copies JAR, creates service)
 * 3. Creates an AMI snapshot
 * 4. Terminates the temporary instance
 * 5. You now have a ready-to-use AMI!
 * 
 * Documentation: https://www.packer.io/docs
 */

// Packer version requirement
packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

// Variables - these can be overridden from command line or GitHub Actions
variable "aws_region" {
  type    = string
  default = "us-east-1"
  description = "AWS region where the AMI will be created"
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
  description = "Instance type to use for building the AMI (free tier eligible)"
}

variable "ami_name" {
  type    = string
  default = "schedemy-app-{{timestamp}}"
  description = "Name for the resulting AMI (timestamp is auto-added)"
}

variable "source_ami_owner" {
  type    = string
  default = "137112412989"  # Amazon's official AMI owner ID
  description = "AWS account ID that owns the base AMI"
}

variable "jar_file_path" {
  type    = string
  default = "./target/EduSched-0.0.1-SNAPSHOT.jar"
  description = "Local path to the JAR file to include in the AMI"
}

variable "app_version" {
  type    = string
  default = "latest"
  description = "Application version (for tagging)"
}

// Local variables (computed values)
locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
  ami_name  = "schedemy-${var.app_version}-${local.timestamp}"
}

// Source configuration - defines the base AMI and how to build
source "amazon-ebs" "schedemy" {
  // AWS Configuration
  region        = var.aws_region
  instance_type = var.instance_type
  
  // Source AMI - we start with Amazon Linux 2023 (latest)
  // This filter finds the most recent Amazon Linux 2023 AMI
  source_ami_filter {
    filters = {
      name                = "al2023-ami-*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = [var.source_ami_owner]
  }
  
  // SSH Configuration - how Packer connects to the instance
  ssh_username = "ec2-user"  // Default user for Amazon Linux
  ssh_timeout  = "10m"
  
  // AMI Configuration
  ami_name        = local.ami_name
  ami_description = "Schedemy Spring Boot Application - Version ${var.app_version}"
  
  // Tags for the resulting AMI (helps with organization and cost tracking)
  tags = {
    Name         = local.ami_name
    Application  = "Schedemy"
    Version      = var.app_version
    Environment  = "Production"
    CreatedBy    = "Packer"
    BuildDate    = local.timestamp
    ManagedBy    = "GitHub-Actions"
  }
  
  // Tags for the temporary instance used during build
  run_tags = {
    Name        = "packer-builder-schedemy"
    Purpose     = "AMI-Building"
    Temporary   = "true"
  }
  
  // EBS Volume Configuration
  launch_block_device_mappings {
    device_name = "/dev/xvda"
    volume_size = 8  // 8 GB (free tier eligible)
    volume_type = "gp3"  // General Purpose SSD (cheaper than gp2)
    delete_on_termination = true
    
    // Optional: Encrypt the volume
    encrypted = false  // Set to true for production
  }
  
  // Snapshot tags
  snapshot_tags = {
    Name        = "${local.ami_name}-snapshot"
    Application = "Schedemy"
  }
  
  // AMI Regions - where to copy the AMI
  // Uncomment if you want the AMI in multiple regions
  // ami_regions = ["us-east-1", "us-west-2"]
  
  // Sharing - who can use this AMI
  // Uncomment to share with specific AWS accounts
  // ami_users = ["123456789012"]
}

// Build configuration - defines what happens during the build
build {
  name    = "schedemy-ami"
  sources = ["source.amazon-ebs.schedemy"]
  
  /*
   * PROVISIONERS
   * These run in order to configure the instance
   */
  
  // 1. Upload the JAR file to the temporary instance
  provisioner "file" {
    source      = var.jar_file_path
    destination = "/tmp/EduSched-0.0.1-SNAPSHOT.jar"
  }
  
  // 2. Wait for cloud-init to finish (important on Amazon Linux)
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait",
      "echo 'Cloud-init completed successfully'"
    ]
  }
  
  // 3. Run Ansible to configure the instance
  provisioner "ansible" {
    playbook_file = "./.ansible/playbooks/configure-instance.yml"
    
    // Extra variables to pass to Ansible
    extra_arguments = [
      "--extra-vars",
      "jar_filename=EduSched-0.0.1-SNAPSHOT.jar app_version=${var.app_version}"
    ]
    
    // Use SSH to connect (Packer handles the connection details)
    use_proxy = false
    
    // Ansible configuration
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_STDOUT_CALLBACK=yaml"
    ]
  }
  
  // 4. Final cleanup and preparation for AMI creation
  provisioner "shell" {
    inline = [
      "echo 'Running final cleanup...'",
      
      // Clean package manager cache
      "sudo yum clean all",
      
      // Remove temporary files
      "sudo rm -rf /tmp/*",
      "sudo rm -rf /var/tmp/*",
      
      // Clear log files (but keep directories)
      "sudo find /var/log -type f -name '*.log' -exec truncate -s 0 {} \\;",
      
      // Remove SSH host keys (will be regenerated on first boot)
      "sudo rm -f /etc/ssh/ssh_host_*",
      
      // Clear bash history
      "cat /dev/null > ~/.bash_history && history -c",
      
      // Clear cloud-init cache (allows it to run on new instances)
      "sudo rm -rf /var/lib/cloud/instances/*",
      
      "echo 'Cleanup completed - instance is ready for AMI creation'"
    ]
  }
  
  /*
   * POST-PROCESSORS
   * These run after the AMI is created
   */
  
  // Create a manifest file with AMI details (useful for automation)
  post-processor "manifest" {
    output     = "packer-manifest.json"
    strip_path = true
    custom_data = {
      version     = var.app_version
      build_time  = local.timestamp
      ami_regions = var.aws_region
    }
  }
}

/*
 * USAGE EXAMPLES:
 * 
 * 1. Basic build:
 *    packer build packer/schedemy-ami.pkr.hcl
 * 
 * 2. Build with custom version:
 *    packer build -var 'app_version=1.2.3' packer/schedemy-ami.pkr.hcl
 * 
 * 3. Build in different region:
 *    packer build -var 'aws_region=us-west-2' packer/schedemy-ami.pkr.hcl
 * 
 * 4. Validate the template:
 *    packer validate packer/schedemy-ami.pkr.hcl
 * 
 * 5. Format the template:
 *    packer fmt packer/schedemy-ami.pkr.hcl
 */

/*
 * IMPORTANT NOTES:
 * 
 * 1. AWS Credentials:
 *    Packer needs AWS credentials to create AMIs. It will use:
 *    - Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
 *    - AWS credentials file (~/.aws/credentials)
 *    - IAM role (if running on EC2)
 * 
 * 2. Required IAM Permissions:
 *    - ec2:RunInstances
 *    - ec2:CreateImage
 *    - ec2:CreateTags
 *    - ec2:DescribeImages
 *    - ec2:DescribeInstances
 *    - ec2:TerminateInstances
 * 
 * 3. Cost:
 *    - Temporary EC2 instance runs for ~5-10 minutes
 *    - Storage for the AMI (8 GB snapshot)
 *    - All within free tier limits!
 * 
 * 4. Time:
 *    - Typical build time: 5-10 minutes
 *    - Depends on instance type and provisioning complexity
 */
