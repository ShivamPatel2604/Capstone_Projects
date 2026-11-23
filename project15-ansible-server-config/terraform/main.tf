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

# Public IP of the machine running Terraform (the Ansible controller)
data "http" "controller_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  controller_cidr = coalesce(var.controller_cidr, "${chomp(data.http.controller_ip.response_body)}/32")
  ansible_dir     = "${path.module}/../ansible"
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

resource "aws_security_group" "nodes" {
  name        = "${var.project_name}-nodes-sg"
  description = "SSH from Ansible controller, HTTP from anywhere"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from Ansible controller"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.controller_cidr]
  }

  ingress {
    description = "HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-nodes-sg"
  }
}

# ---------------------------------------------------------------------------
# SSH key pair used by the Ansible controller
# ---------------------------------------------------------------------------
resource "tls_private_key" "ansible" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "ansible" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.ansible.public_key_openssh
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.ansible.private_key_openssh
  filename        = "${local.ansible_dir}/project15-key.pem"
  file_permission = "0600"
}

# ---------------------------------------------------------------------------
# Managed nodes (no user_data: Ansible does all configuration)
# ---------------------------------------------------------------------------
resource "aws_instance" "node" {
  count = var.node_count

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.nodes.id]
  key_name               = aws_key_pair.ansible.key_name

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
    Role = "webserver"
  }

  depends_on = [aws_route_table_association.public]
}

# Ansible inventory generated from the created instances
resource "local_file" "inventory" {
  filename        = "${local.ansible_dir}/inventory.ini"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/inventory.tftpl", {
    nodes    = aws_instance.node
    key_file = "project15-key.pem"
  })
}
