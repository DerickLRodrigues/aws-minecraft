terraform {
  required_version = ">= 1.6, < 2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
provider "aws" {
  region = "sa-east-1"
  default_tags {
    tags = { Project = "prominence-ii", ManagedBy = "Terraform" }
  }
}
data "aws_ec2_instance_type_offerings" "eligible" {
  location_type = "availability-zone"
  filter {
    name   = "instance-type"
    values = ["m7i-flex.xlarge"]
  }
}
data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
resource "aws_vpc" "game" {
  cidr_block           = "10.76.0.0/24"
  enable_dns_hostnames = true
  tags                 = { Name = "prominence" }
}
resource "aws_internet_gateway" "game" {
  vpc_id = aws_vpc.game.id
}
resource "aws_subnet" "game" {
  vpc_id            = aws_vpc.game.id
  cidr_block        = "10.76.0.0/26"
  availability_zone = sort(tolist(setintersection(data.aws_availability_zones.available.names, data.aws_ec2_instance_type_offerings.eligible.locations)))[0]
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.game.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.game.id
  }
}
resource "aws_route_table_association" "public" {
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.game.id
}
resource "aws_security_group" "game" {
  name_prefix = "prominence-"
  vpc_id      = aws_vpc.game.id
  description = "Minecraft from approved addresses"
}
resource "aws_vpc_security_group_ingress_rule" "players" {
  for_each          = var.player_cidrs
  security_group_id = aws_security_group.game.id
  ip_protocol       = "tcp"
  from_port         = 25565
  to_port           = 25565
  cidr_ipv4         = each.value
}
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.game.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_iam_role" "ssm" {
  name_prefix = "prominence-ssm-"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_instance_profile" "server" {
  name_prefix = "prominence-"
  role        = aws_iam_role.ssm.name
}
resource "aws_instance" "server" {
  ami                                  = nonsensitive(data.aws_ssm_parameter.al2023.value)
  instance_type                        = "m7i-flex.xlarge"
  subnet_id                            = aws_subnet.game.id
  associate_public_ip_address          = true
  vpc_security_group_ids               = [aws_security_group.game.id]
  iam_instance_profile                 = aws_iam_instance_profile.server.name
  instance_initiated_shutdown_behavior = "stop"
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.disk_gib
    encrypted             = true
    delete_on_termination = false
    tags                  = { Name = "prominence-system-world", Backup = "prominence" }
  }
  user_data_base64 = base64gzip(templatefile("${path.module}/bootstrap.sh.tftpl", {
    install = filebase64("${path.module}/install-pack.sh")
    service = filebase64("${path.module}/minecraft.service")
    players = base64encode(jsonencode(var.players))
  }))
  user_data_replace_on_change = true
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [ami]
    precondition {
      condition     = var.accept_minecraft_eula
      error_message = "Leia a EULA do Minecraft e registre seu aceite no terraform.tfvars."
    }
  }
  depends_on = [aws_route_table_association.public, aws_iam_role_policy_attachment.ssm, aws_vpc_security_group_egress_rule.https]
  tags       = { Name = "prominence-ii", Schedule = "on-demand" }
}
