


resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "this" {
  key_name   = var.key_name
  public_key = tls_private_key.this.public_key_openssh
  provisioner "local-exec" { # Create "my-aws-key-pair.pem" to your computer!!
    command = <<-EOT
      echo '${tls_private_key.this.private_key_pem}' > ${var.key_name}.pem
      chmod 400 ${var.key_name}.pem
    EOT
  }
  tags = merge(var.tags, {
    Name = var.key_name
  })
}

resource "aws_default_vpc" "this" {
  tags = merge(var.tags, {
    Name = "Default VPC"
  })
}


# -------------------------
# Security groups
# -------------------------

# SSH access
resource "aws_security_group" "ssh" {
  name        = "ssh-access"
  description = "Allow SSH access"
  vpc_id      = aws_default_vpc.this.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr] # restrict to your IP in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "ssh-access"
  })
}

# Control Plane
resource "aws_security_group" "sg_control_plane" {
  name        = "control-plane-access"
  description = "Kubernetes control plane access"
  vpc_id      = aws_default_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "control-plane-access" })
}

# Worker nodes
resource "aws_security_group" "sg_workers" {
  name        = "workers-access"
  description = "Kubernetes worker nodes access"
  vpc_id      = aws_default_vpc.this.id

  # keep public NodePort here or move to aws_security_group_rule as well
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "workers-access" })
}

# -------------------------
# Cross-SG rules
# -------------------------

# Control plane: allow K8s API from workers
resource "aws_security_group_rule" "cp_api_from_workers" {
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.sg_control_plane.id
  source_security_group_id = aws_security_group.sg_workers.id
  description              = "K8s API from workers"
}

# Control plane: allow Calico VXLAN from workers
resource "aws_security_group_rule" "cp_calico_from_workers" {
  type                     = "ingress"
  from_port                = 4789
  to_port                  = 4789
  protocol                 = "udp"
  security_group_id        = aws_security_group.sg_control_plane.id
  source_security_group_id = aws_security_group.sg_workers.id
  description              = "Calico VXLAN from workers"
}

# Workers: allow kubelet API from control plane
resource "aws_security_group_rule" "workers_kubelet_from_cp" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.sg_workers.id
  source_security_group_id = aws_security_group.sg_control_plane.id
  description              = "Kubelet API from control plane"
}

# Workers: Calico typha VXLAN from workers (peer) — self reference
resource "aws_security_group_rule" "workers_calico_typha_from_workers" {
  type              = "ingress"
  from_port         = 5473
  to_port           = 5473
  protocol          = "tcp"
  security_group_id = aws_security_group.sg_workers.id
  # either of the following works; pick one:
  # self = true
  source_security_group_id = aws_security_group.sg_workers.id
  description              = "Calico typha VXLAN from worker peers"
}

# Workers: Calico VXLAN from workers (peer) — self reference
resource "aws_security_group_rule" "workers_calico_from_workers" {
  type              = "ingress"
  from_port         = 4789
  to_port           = 4789
  protocol          = "udp"
  security_group_id = aws_security_group.sg_workers.id
  # either of the following works; pick one:
  # self = true
  source_security_group_id = aws_security_group.sg_workers.id
  description              = "Calico VXLAN from worker peers"
}

# Workers: Calico VXLAN from control plane
resource "aws_security_group_rule" "workers_calico_from_cp" {
  type                     = "ingress"
  from_port                = 4789
  to_port                  = 4789
  protocol                 = "udp"
  security_group_id        = aws_security_group.sg_workers.id
  source_security_group_id = aws_security_group.sg_control_plane.id
  description              = "Calico VXLAN from control plane"
}

# Instances definition

locals {
  nodes = {
    control-plane = { role = "control-plane", sg_ids = [aws_security_group.ssh.id, aws_security_group.sg_control_plane.id], instance_type = "t3.medium" }
    worker01      = { role = "worker", sg_ids = [aws_security_group.ssh.id, aws_security_group.sg_workers.id], instance_type = "t3.small" }
    worker02      = { role = "worker", sg_ids = [aws_security_group.ssh.id, aws_security_group.sg_workers.id], instance_type = "t3.small" }
  }
}

resource "aws_instance" "nodes" {
  for_each                    = local.nodes
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = each.value.instance_type
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = true
  vpc_security_group_ids      = each.value.sg_ids

  # Cloud-init to set hostname
  user_data = <<-EOF
              #!/bin/bash
              hostnamectl set-hostname ${each.key}
              EOF

  tags = merge(var.tags, {
    Name = each.key
    Role = each.value.role
  })
}
