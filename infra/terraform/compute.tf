resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${local.name_prefix}-cluster"
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/govnotes/${var.environment}/app"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.app.arn
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.name_prefix}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.app_task.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = var.app_image
      essential = true
      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "NODE_ENV", value = "production" },
        { name = "PORT", value = "3000" },
        { name = "LOG_LEVEL", value = "info" }
      ]
      secrets = [
        { name = "DATABASE_URL", valueFrom = aws_secretsmanager_secret.db_url.arn },
        { name = "JWT_SIGNING_KEY", valueFrom = aws_secretsmanager_secret.jwt_signing_key.arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "app"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = "${local.name_prefix}-app"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 3
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [for s in aws_subnet.private_app : s.id]
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = 3000
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
}

# ------------------------------------------------------------------------
# Bastion / operator jumphost
#
# Small EC2 that operators SSM-session into for emergency break-glass to
# the data tier. Not reachable from the public internet; only entry is
# SSM. Kept minimal on purpose.
# ------------------------------------------------------------------------

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_security_group" "bastion" {
  name        = "${local.name_prefix}-bastion-sg"
  description = "Break-glass bastion. SSM-only, no inbound."
  vpc_id      = aws_vpc.main.id

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-bastion-sg"
  }
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.small"
  subnet_id              = values(aws_subnet.private_app)[0].id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
    kms_key_id  = aws_kms_key.app.arn
  }

  monitoring = true

  tags = {
    Name = "${local.name_prefix}-bastion"
    Role = "bastion"
  }
}

# Secondary scratch volume the on-call engineer uses to stage pg_dump
# output during break-glass. Re-created fresh each incident.
# TODO(platform): re-provision this with encryption on; leftover from
# the pre-FedRAMP build of the jumphost.
resource "aws_ebs_volume" "bastion_scratch" {
  availability_zone = aws_instance.bastion.availability_zone
  size              = 50
  type              = "gp3"
  encrypted         = false

  tags = {
    Name = "${local.name_prefix}-bastion-scratch"
  }
}

resource "aws_volume_attachment" "bastion_scratch" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.bastion_scratch.id
  instance_id = aws_instance.bastion.id
}
