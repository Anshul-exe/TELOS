# ---------------------------------------------------------------------------
# Bastion module — the telos-bastion host (baseArch.md).
# Amazon Linux 2023, IMDSv2 enforced, SSM instance profile attached, SSH
# restricted to the operator's IP only.
# ---------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  base_tags = merge(var.tags, {
    Module = "bastion"
  })
}

# Latest Amazon Linux 2023 AMI (x86_64), resolved via SSM public parameter.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "bastion" {
  name_prefix = "${var.name}-sg-"
  description = "Bastion SG - SSH from the operator IP only."
  vpc_id      = var.vpc_id

  tags = merge(local.base_tags, { Name = "${var.name}-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.bastion.id
  description       = "SSH from the operator IP"
  cidr_ipv4         = var.operator_ip_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.bastion.id
  description       = "Allow all outbound (kubectl to API, SSM, package updates)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_instance" "bastion" {
  ami                  = data.aws_ssm_parameter.al2023.value
  instance_type        = var.instance_type
  subnet_id            = var.subnet_id
  iam_instance_profile = var.instance_profile_name
  key_name             = var.key_name

  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  # Enforce IMDSv2.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(local.base_tags, { Name = var.name })
}
