variable "region" {
  description = "The AWS region where the Redshift Serverless resources will be deployed."
  type        = string
  default     = "us-west-2"
}

variable "namespace_name" {
  description = "The name of the Redshift Serverless namespace."
  type        = string
  default     = "my-redshift-namespace"
}

variable "workgroup_name" {
  description = "The name of the Redshift Serverless workgroup."
  type        = string
  default     = "my-redshift-workgroup"
}

variable "base_capacity" {
  description = "The base capacity for the Redshift Serverless workgroup."
  type        = number
  default     = 4
}

variable "max_capacity" {
  description = "The maximum capacity for the Redshift Serverless workgroup."
  type        = number
  default     = 8
}

variable "namespace_admins" {
  description = "List of IAM users or roles that can manage the namespace."
  type        = list(string)
  default     = []
}

variable "endpoint_name" {
  description = "The name of the Redshift Serverless endpoint."
  type        = string
  default     = "my-redshift-endpoint"
}