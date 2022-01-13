# Data Block
data "aws_ami" "amazon-linux-2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

# Security Group
resource "aws_security_group" "jenkins-sg" {
  name        = "jenkins-sg"
  description = "security group that allows ssh and all egress traffic"
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "jenkins-sg"
  }
}

data "cloudinit_config" "jenkins_config" {
  part {
    content_type = "text/cloud-config"
    content      = file("${path.module}/user_data.yaml")
  }
}

# EC2 Instance
resource "aws_instance" "jenkins" {
  ami             = data.aws_ami.amazon-linux-2.id
  instance_type   = "t3.micro"
  key_name        = "michel"
  security_groups = [aws_security_group.jenkins-sg.name]

  user_data = data.cloudinit_config.jenkins_config.rendered

  tags = {
    "Name" = "Jenkins"
  }
}

output "jenkins_url" {
  value       = "http://${aws_instance.jenkins.public_ip}:8080"
  description = "The host address of jenkins server"
}