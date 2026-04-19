resource "aws_lb" "app" {
  name               = "${local.name_prefix}-app-alb"
  load_balancer_type = "application"
  subnets            = [for s in aws_subnet.public : s.id]
  security_groups    = [aws_security_group.alb.id]
  internal           = false

  drop_invalid_header_fields = true
  enable_deletion_protection = true

  access_logs {
    bucket  = aws_s3_bucket.backups.id
    prefix  = "alb-access-logs"
    enabled = true
  }

  tags = {
    Name = "${local.name_prefix}-app-alb"
  }
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-app-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    matcher             = "200"
  }

  tags = {
    Name = "${local.name_prefix}-app-tg"
  }
}

# Primary HTTPS listener — customer traffic to app.gov.govnotes.com
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Port-80 listener. See network.tf TODO about wiring this to a permanent
# redirect to 443. Today it just 404s, which is what we want for now.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "not found"
      status_code  = "404"
    }
  }
}

# ------------------------------------------------------------------------
# Legacy API listener
#
# A handful of older API integrations at our existing government customers
# talk to a separate hostname (legacy-api.gov.govnotes.com). The hostname
# maps to the same ALB but uses an older TLS policy for legacy API
# compatibility. Tracked for deprecation in the Q3 API-modernization epic.
# ------------------------------------------------------------------------

resource "aws_lb_listener" "legacy_api" {
  load_balancer_arn = aws_lb.app.arn
  port              = 8443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
