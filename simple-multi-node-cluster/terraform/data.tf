# Ubuntu 22.04 LTS (Jammy) AMD64
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"] # Canonical

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
