variable "aws_conf" {
  type = "map"
  default = {}
}

variable "vpc_conf" {
  type = "map"
  default = {}
}

variable "vault_conf" {
  type = "map"
  default = {
    id = "vault"
    version = "0.7.3"
    capacity = "2"
    internal = "true"
    port = "8200"
    dynamodb.hash_key = "key"
    dynamodb.read_capacity = "5"
    dynamodb.write_capacity = "5"
  }
}

variable "subnet-type" {
  default = {
    "true" = "subnets_private"
    "false" = "subnets_public"
  }
}

variable "public_ip" {
  default = {
    "true" = "false"
    "false" = "true"
  }
}
