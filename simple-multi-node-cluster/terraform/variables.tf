variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Terraform   = "true"
    Environment = "dev"
  }
}

variable "my_ip_cidr" {
  description = "Your IP address in CIDR notation (e.g., xx.x.x.xx/32)"
  type        = string
}

variable "key_name" {
  description = "Name of the key pair"
  type        = string
  default     = "fab-aws-key-pair"
}
