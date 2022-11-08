# Use default VPC
data "aws_vpc" "default" {
  default = true
}

# Fetch subnets for default VPCs
data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

data "aws_availability_zones" "available" {
}


# Security Group
# Add security group for EFS
resource "aws_security_group" "ingress-efs" {
  name   = "ingress-efs"
  vpc_id = data.aws_vpc.default.id

  ingress {

    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
# Jenkins Security Group
resource "aws_security_group" "jenkins" {
  name        = "jenkins-sg"
  description = "security group that allows ssh and all egress traffic"
  vpc_id = data.aws_vpc.default.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EFS
resource "aws_efs_file_system" "jenkins" {
  creation_token   = "Jenkins-EFS"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = "true"
  tags = {
    Name = "JenkinsHomeEFS"
  }
}

resource "aws_efs_mount_target" "jenkins-efs-mount" {
  count           = length(tolist(data.aws_subnet_ids.default.ids))
  file_system_id  = aws_efs_file_system.jenkins.id
  subnet_id       = element(tolist(data.aws_subnet_ids.default.ids), count.index)
  security_groups = [aws_security_group.ingress-efs.id]
}

resource "aws_efs_access_point" "jenkins" {
  file_system_id = aws_efs_file_system.jenkins.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/jenkinsHome"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = 750
    }
  }
}

# ECS
resource "aws_ecs_cluster" "main" {
  name = "Jenkins-cluster"
}

resource "aws_ecs_task_definition" "jenkins" {
  family                   = "jenkins"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions = jsonencode([{
   name        = "jenkins-container"
   image       = "jenkins/jenkins:latest"
   essential   = true
   logConfiguration: {
      "logDriver": "awslogs",
      "secretOptions": null,
      "options": {
          "awslogs-group": "/ecs/jenkins",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
      }
   },
   mountPoints: [{
      "readOnly": null,
      "containerPath": "/var/jenkins_home",
      "sourceVolume": "jenkinsHome"
   }],
   portMappings = [{
     protocol      = "tcp"
     containerPort = 8080
     hostPort      = 8080
   }]
  }])
  volume {
    name = "jenkinsHome"

    efs_volume_configuration {
      file_system_id          = aws_efs_file_system.jenkins.id
      root_directory          = "/"
      transit_encryption      = "ENABLED"
      authorization_config {
        access_point_id =  aws_efs_access_point.jenkins.id
        iam             = "DISABLED"
      }
    }
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "jenkins-ecsTaskExecutionRole"
 
  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "ecs-tasks.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}

resource "aws_ecs_service" "jenkins" {
  name            = "jenkins"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.jenkins.arn
  desired_count   = 1
  
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  launch_type                        = "FARGATE"
  scheduling_strategy                = "REPLICA"
 
  network_configuration {
   security_groups  = [aws_security_group.jenkins.id]
   subnets          = data.aws_subnet_ids.default.ids
   assign_public_ip = true
  }
}
 
resource "aws_iam_role_policy_attachment" "ecs-task-execution-role-policy-attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
