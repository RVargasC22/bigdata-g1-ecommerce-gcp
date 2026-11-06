variable "project_id" {
  type    = string
  default = "bigdata-g1-ecommerce-1105"
}
variable "region" {
  type    = string
  default = "us-central1"
}
variable "bucket" {
  type    = string
  default = "bigdata-g1-ecommerce-1105-raw"
}
variable "dataset" {
  type    = string
  default = "ecommerce"
}
variable "dr_dataset" {
  type    = string
  default = "ecommerce_dr"
}
variable "topic" {
  type    = string
  default = "rees46-events"
}
variable "subscription" {
  type    = string
  default = "rees46-events-dataflow"
}
# Personal accounts: set in terraform.tfvars (not committed; copy terraform.tfvars.example)
variable "alert_email" {
  type = string
}
# Users allowed to read policy-tagged columns (user_id, customer_unique_id)
variable "full_readers" {
  type = list(string)
}
