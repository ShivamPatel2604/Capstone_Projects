data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# ---------------------------------------------------------------------------
# Networking: one public subnet per Availability Zone
# ---------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${data.aws_availability_zones.available.names[count.index]}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Security groups: internet -> ALB:80 -> instances:80
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Public HTTP to the load balancer"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_web" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Traffic and health checks to the web servers"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.web.id
}

resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "HTTP from the ALB only - no SSH, management via SSM"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-web-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "web_from_alb" {
  security_group_id            = aws_security_group.web.id
  description                  = "HTTP from the load balancer only"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "web_all" {
  security_group_id = aws_security_group.web.id
  description       = "Outbound for SSM, CloudWatch and package repos"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# IAM: SSM management + CloudWatch agent publishing
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "web" {
  name               = "${var.project_name}-web-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.web.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.web.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "web" {
  name = "${var.project_name}-web-profile"
  role = aws_iam_role.web.name
}

# ---------------------------------------------------------------------------
# Monitored web servers (detailed monitoring = 1-minute EC2 metrics)
# ---------------------------------------------------------------------------
resource "aws_instance" "web" {
  count = var.instance_count

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[count.index % length(aws_subnet.public)].id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.web.name
  monitoring             = true

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/templates/user_data.sh", {
    server_name = "web-${count.index + 1}"
  })

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = "${var.project_name}-web-${count.index + 1}"
    Role = "monitored-web"
  }

  depends_on = [
    aws_route_table_association.public,
    aws_iam_role_policy_attachment.ssm_core,
    aws_iam_role_policy_attachment.cloudwatch_agent,
  ]
}

# ---------------------------------------------------------------------------
# Application Load Balancer (source of request / latency / error metrics)
# ---------------------------------------------------------------------------
resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  drop_invalid_header_fields = true

  tags = {
    Name = "${var.project_name}-alb"
  }
}

resource "aws_lb_target_group" "web" {
  name                 = "${var.project_name}-tg"
  port                 = 80
  protocol             = "HTTP"
  target_type          = "instance"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = "/health"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.project_name}-tg"
  }
}

resource "aws_lb_target_group_attachment" "web" {
  count = var.instance_count

  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# ---------------------------------------------------------------------------
# CloudWatch alarms (shown on the dashboard)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  count = var.instance_count

  alarm_name          = "${var.project_name}-web-${count.index + 1}-high-cpu"
  alarm_description   = "CPU above ${var.cpu_alarm_threshold}% on web-${count.index + 1}"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = aws_instance.web[count.index].id }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = var.cpu_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
}

resource "aws_cloudwatch_metric_alarm" "high_memory" {
  count = var.instance_count

  alarm_name          = "${var.project_name}-web-${count.index + 1}-high-memory"
  alarm_description   = "Memory used above ${var.memory_alarm_threshold}% on web-${count.index + 1} (CloudWatch agent)"
  namespace           = "CWAgent"
  metric_name         = "mem_used_percent"
  dimensions          = { InstanceId = aws_instance.web[count.index].id }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = var.memory_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.project_name}-unhealthy-hosts"
  alarm_description   = "At least one target behind the ALB is failing health checks"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = { LoadBalancer = aws_lb.app.arn_suffix, TargetGroup = aws_lb_target_group.web.arn_suffix }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "high_latency" {
  alarm_name          = "${var.project_name}-high-latency"
  alarm_description   = "ALB target response time p90 above ${var.latency_alarm_threshold}s"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = { LoadBalancer = aws_lb.app.arn_suffix }
  extended_statistic  = "p90"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = var.latency_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${var.project_name}-target-5xx"
  alarm_description   = "Web servers returned 5xx errors through the ALB"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = aws_lb.app.arn_suffix }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

# ---------------------------------------------------------------------------
# CloudWatch dashboard
# ---------------------------------------------------------------------------
locals {
  lb_dim = ["LoadBalancer", aws_lb.app.arn_suffix]
  tg_dim = ["TargetGroup", aws_lb_target_group.web.arn_suffix, "LoadBalancer", aws_lb.app.arn_suffix]

  # One line per web server for a given namespace/metric
  per_instance = {
    for m in [
      { key = "cpu", ns = "AWS/EC2", name = "CPUUtilization", suffix = "", opts = {} },
      { key = "net_in", ns = "AWS/EC2", name = "NetworkIn", suffix = " in", opts = {} },
      { key = "net_out", ns = "AWS/EC2", name = "NetworkOut", suffix = " out", opts = {} },
      { key = "status", ns = "AWS/EC2", name = "StatusCheckFailed", suffix = " status check failed", opts = { stat = "Maximum", yAxis = "right" } },
      { key = "mem", ns = "CWAgent", name = "mem_used_percent", suffix = "", opts = {} },
      { key = "disk", ns = "CWAgent", name = "disk_used_percent", suffix = "", opts = {} },
      { key = "iowait", ns = "CWAgent", name = "cpu_usage_iowait", suffix = " iowait %", opts = { yAxis = "right" } },
      { key = "tcp", ns = "CWAgent", name = "netstat_tcp_established", suffix = " TCP conns", opts = {} },
      ] : m.key => [
      for i in aws_instance.web : [m.ns, m.name, "InstanceId", i.id, merge({ label = "${i.tags["Name"]}${m.suffix}" }, m.opts)]
    ]
  }

  all_alarm_arns = concat(
    aws_cloudwatch_metric_alarm.high_cpu[*].arn,
    aws_cloudwatch_metric_alarm.high_memory[*].arn,
    [
      aws_cloudwatch_metric_alarm.unhealthy_hosts.arn,
      aws_cloudwatch_metric_alarm.high_latency.arn,
      aws_cloudwatch_metric_alarm.target_5xx.arn,
    ]
  )

  graph_defaults = {
    view   = "timeSeries"
    region = var.aws_region
    period = var.dashboard_period
  }

  dashboard_widgets = [
    # Row 0: title + alarm status
    {
      type = "text", x = 0, y = 0, width = 24, height = 2
      properties = {
        markdown = join("\n", [
          "# Project 21 - CloudWatch Monitoring Dashboard",
          "App: [${aws_lb.app.dns_name}](http://${aws_lb.app.dns_name}) | ${var.instance_count} x ${var.instance_type} behind ALB `${aws_lb.app.name}` | Region `${var.aws_region}`",
        ])
      }
    },
    {
      type = "alarm", x = 0, y = 2, width = 24, height = 3
      properties = {
        title  = "Alarm status"
        alarms = local.all_alarm_arns
        sortBy = "stateUpdatedTimestamp"
      }
    },

    # Row 1: headline numbers
    {
      type = "metric", x = 0, y = 5, width = 24, height = 4
      properties = {
        title     = "Current performance (last value)"
        view      = "singleValue"
        region    = var.aws_region
        period    = 300
        sparkline = true
        metrics = [
          concat(["AWS/ApplicationELB", "RequestCount"], local.lb_dim, [{ stat = "Sum", label = "Requests (5 min)" }]),
          concat(["AWS/ApplicationELB", "TargetResponseTime"], local.lb_dim, [{ stat = "p90", label = "Latency p90 (s)" }]),
          concat(["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count"], local.lb_dim, [{ stat = "Sum", label = "5xx errors" }]),
          concat(["AWS/ApplicationELB", "HealthyHostCount"], local.tg_dim, [{ stat = "Minimum", label = "Healthy hosts" }]),
          concat(["AWS/ApplicationELB", "UnHealthyHostCount"], local.tg_dim, [{ stat = "Maximum", label = "Unhealthy hosts" }]),
        ]
      }
    },

    # Row 2: load balancer traffic
    {
      type = "metric", x = 0, y = 9, width = 8, height = 6
      properties = merge(local.graph_defaults, {
        title   = "ALB requests per minute"
        stat    = "Sum"
        metrics = [concat(["AWS/ApplicationELB", "RequestCount"], local.lb_dim, [{ label = "Requests" }])]
        yAxis   = { left = { min = 0 } }
      })
    },
    {
      type = "metric", x = 8, y = 9, width = 8, height = 6
      properties = merge(local.graph_defaults, {
        title = "Target response time (seconds)"
        metrics = [
          concat(["AWS/ApplicationELB", "TargetResponseTime"], local.lb_dim, [{ stat = "p50", label = "p50" }]),
          concat(["AWS/ApplicationELB", "TargetResponseTime"], local.lb_dim, [{ stat = "p90", label = "p90" }]),
          concat(["AWS/ApplicationELB", "TargetResponseTime"], local.lb_dim, [{ stat = "p99", label = "p99" }]),
        ]
        yAxis = { left = { min = 0 } }
        annotations = {
          horizontal = [{ label = "Latency alarm", value = var.latency_alarm_threshold, color = "#d62728" }]
        }
      })
    },
    {
      type = "metric", x = 16, y = 9, width = 8, height = 6
      properties = merge(local.graph_defaults, {
        title   = "HTTP responses by status code"
        stat    = "Sum"
        stacked = true
        metrics = [
          concat(["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count"], local.lb_dim, [{ label = "2xx", color = "#2ca02c" }]),
          concat(["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count"], local.lb_dim, [{ label = "4xx", color = "#ff7f0e" }]),
          concat(["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count"], local.lb_dim, [{ label = "5xx (target)", color = "#d62728" }]),
          concat(["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count"], local.lb_dim, [{ label = "5xx (ALB)", color = "#9467bd" }]),
        ]
      })
    },

    # Row 3: compute
    {
      type = "metric", x = 0, y = 15, width = 8, height = 6
      properties = merge(local.graph_defaults, {
        title   = "EC2 CPU utilization (%)"
        stat    = "Average"
        metrics = local.per_instance["cpu"]
        yAxis   = { left = { min = 0, max = 100 } }
        annotations = {
          horizontal = [{ label = "CPU alarm", value = var.cpu_alarm_threshold, color = "#d62728" }]
        }
      })
    },
    {
      type = "metric", x = 8, y = 15, width = 8, height = 6
      properties = merge(local.graph_defaults, {
        title   = "Memory used (%) - CloudWatch agent"
        stat    = "Average"
        metrics = local.per_instance["mem"]
        yAxis   = { left = { min = 0, max = 100 } }
        annotations = {
          horizontal = [{ label = "Memory alarm", value = var.memory_alarm_threshold, color = "#d62728" }]
        }
      })
    },
    {
      type = "metric", x = 16, y = 15, width = 8, height = 6
      properties = merge(local.graph_defaults, {
        title   = "Root disk used (%) - CloudWatch agent"
        stat    = "Average"
        metrics = local.per_instance["disk"]
        yAxis   = { left = { min = 0, max = 100 } }
      })
    },

    # Row 4: network and health
    {
      type = "metric", x = 0, y = 21, width = 8, height = 6
      properties = merge(local.graph_defaults, {
        title   = "Network in / out (bytes)"
        stat    = "Sum"
        metrics = concat(local.per_instance["net_in"], local.per_instance["net_out"])
      })
    },
    {
      type = "metric", x = 8, y = 21, width = 8, height = 6
      properties = merge(local.graph_defaults, {
        title   = "Established TCP connections / CPU iowait (%)"
        stat    = "Average"
        metrics = concat(local.per_instance["tcp"], local.per_instance["iowait"])
      })
    },
    {
      type = "metric", x = 16, y = 21, width = 8, height = 6
      properties = merge(local.graph_defaults, {
        title = "Target health and status checks"
        metrics = concat(
          [
            concat(["AWS/ApplicationELB", "HealthyHostCount"], local.tg_dim, [{ stat = "Minimum", label = "Healthy hosts", color = "#2ca02c" }]),
            concat(["AWS/ApplicationELB", "UnHealthyHostCount"], local.tg_dim, [{ stat = "Maximum", label = "Unhealthy hosts", color = "#d62728" }]),
          ],
          local.per_instance["status"]
        )
        yAxis = { left = { min = 0 }, right = { min = 0, max = 1 } }
      })
    },
  ]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-performance"
  dashboard_body = jsonencode({ widgets = local.dashboard_widgets })
}
