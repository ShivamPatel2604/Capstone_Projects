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

locals {
  # Files the CloudWatch agent tails -> one log group per source
  log_sources = {
    "httpd-access" = "/var/log/httpd/access_log"
    "httpd-error"  = "/var/log/httpd/error_log"
    "system"       = "/var/log/messages"
    "secure"       = "/var/log/secure"
  }

  log_group_names = { for key, path in local.log_sources : key => "/${var.project_name}/${key}" }

  metric_namespace = "Project17/WebServer"

  # Apache combined log format: ip ident user [time] "request" status bytes "referer" "user-agent"
  access_log_pattern_fields = "ip, id, user, timestamp, request, status_code, bytes, referer, user_agent"

  # Parameter name must start with "AmazonCloudWatch-" so that the
  # CloudWatchAgentServerPolicy allows the agent to read it.
  agent_config_parameter = "AmazonCloudWatch-${var.project_name}"
}

# ---------------------------------------------------------------------------
# Networking
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
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
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
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# HTTP only, no SSH. The instance is managed through Systems Manager and the
# CloudWatch agent pushes logs over outbound HTTPS.
resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "HTTP only - no SSH, management via SSM"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound for SSM, CloudWatch Logs and package repos"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-web-sg"
  }
}

# ---------------------------------------------------------------------------
# IAM: SSM management + permission for the CloudWatch agent to ship logs
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
# Web server (log source). The CloudWatch agent is NOT installed here; it is
# installed afterwards with SSM Run Command (see README).
# ---------------------------------------------------------------------------
resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.web.name

  user_data_replace_on_change = true
  user_data                   = file("${path.module}/templates/user_data.sh")

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
    Name = "${var.project_name}-web"
    Role = "log-source"
  }

  depends_on = [
    aws_route_table_association.public,
    aws_iam_role_policy_attachment.ssm_core,
    aws_iam_role_policy_attachment.cloudwatch_agent,
  ]
}

# ---------------------------------------------------------------------------
# CloudWatch Logs destination
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  for_each = local.log_group_names

  name              = each.value
  retention_in_days = var.log_retention_days
}

# CloudWatch agent configuration, stored centrally in Parameter Store
resource "aws_ssm_parameter" "agent_config" {
  name        = local.agent_config_parameter
  description = "CloudWatch agent log forwarding config for ${var.project_name}"
  type        = "String"

  value = jsonencode({
    agent = {
      run_as_user = "root"
    }
    logs = {
      force_flush_interval = 5
      logs_collected = {
        files = {
          collect_list = [
            for key, path in local.log_sources : {
              file_path       = path
              log_group_name  = aws_cloudwatch_log_group.this[key].name
              log_stream_name = "{instance_id}"
              timezone        = "UTC"
            }
          ]
        }
      }
    }
  })
}

# Turn access-log lines into metrics for the dashboard
resource "aws_cloudwatch_log_metric_filter" "http_requests" {
  name           = "${var.project_name}-http-requests"
  log_group_name = aws_cloudwatch_log_group.this["httpd-access"].name
  pattern        = "[${local.access_log_pattern_fields}]"

  metric_transformation {
    name      = "HttpRequests"
    namespace = local.metric_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "http_4xx" {
  name           = "${var.project_name}-http-4xx"
  log_group_name = aws_cloudwatch_log_group.this["httpd-access"].name
  pattern        = "[${replace(local.access_log_pattern_fields, "status_code", "status_code=4*")}]"

  metric_transformation {
    name      = "Http4xx"
    namespace = local.metric_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "http_5xx" {
  name           = "${var.project_name}-http-5xx"
  log_group_name = aws_cloudwatch_log_group.this["httpd-access"].name
  pattern        = "[${replace(local.access_log_pattern_fields, "status_code", "status_code=5*")}]"

  metric_transformation {
    name      = "Http5xx"
    namespace = local.metric_namespace
    value     = "1"
  }
}

# ---------------------------------------------------------------------------
# Central log dashboard
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "logs" {
  dashboard_name = "${var.project_name}-logs"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# Project 17 - Central Log Management\nLogs forwarded by the CloudWatch agent from `${var.project_name}-web` (${var.aws_region})"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 12
        height = 6
        properties = {
          title   = "HTTP requests vs errors (from access log)"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          stat    = "Sum"
          period  = 60
          metrics = [
            [local.metric_namespace, "HttpRequests", { label = "Requests" }],
            [local.metric_namespace, "Http4xx", { label = "4xx" }],
            [local.metric_namespace, "Http5xx", { label = "5xx" }],
          ]
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 2
        width  = 12
        height = 6
        properties = {
          title  = "Requests by HTTP status code"
          region = var.aws_region
          view   = "pie"
          query  = "SOURCE '${aws_cloudwatch_log_group.this["httpd-access"].name}' | parse @message '* - - [*] \"* * *\" * *' as client_ip, ts, method, path, protocol, status, rest | stats count(*) as requests by status"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "Top requested paths"
          region = var.aws_region
          view   = "table"
          query  = "SOURCE '${aws_cloudwatch_log_group.this["httpd-access"].name}' | parse @message '* - - [*] \"* * *\" * *' as client_ip, ts, method, path, protocol, status, rest | stats count(*) as hits by path, status | sort hits desc | limit 10"
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "Log volume per source"
          region = var.aws_region
          view   = "bar"
          query  = "SOURCE '${aws_cloudwatch_log_group.this["httpd-access"].name}' | SOURCE '${aws_cloudwatch_log_group.this["httpd-error"].name}' | SOURCE '${aws_cloudwatch_log_group.this["system"].name}' | SOURCE '${aws_cloudwatch_log_group.this["secure"].name}' | stats count(*) as events by @log"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 14
        width  = 24
        height = 6
        properties = {
          title  = "Latest Apache access log entries"
          region = var.aws_region
          view   = "table"
          query  = "SOURCE '${aws_cloudwatch_log_group.this["httpd-access"].name}' | fields @timestamp, @logStream, @message | sort @timestamp desc | limit 20"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 20
        width  = 12
        height = 6
        properties = {
          title  = "Apache error log"
          region = var.aws_region
          view   = "table"
          query  = "SOURCE '${aws_cloudwatch_log_group.this["httpd-error"].name}' | fields @timestamp, @message | sort @timestamp desc | limit 20"
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 20
        width  = 12
        height = 6
        properties = {
          title  = "System & security logs"
          region = var.aws_region
          view   = "table"
          query  = "SOURCE '${aws_cloudwatch_log_group.this["system"].name}' | SOURCE '${aws_cloudwatch_log_group.this["secure"].name}' | fields @timestamp, @log, @message | sort @timestamp desc | limit 20"
        }
      },
    ]
  })
}
