variable "subscription_id" {
  description = "Azure subscription ID (required by azurerm 4.x)."
  type        = string
}

variable "yourname" {
  description = "Your name — makes resource names unique."
  type        = string
}

variable "location" {
  description = "Azure region. Chosen from the VM pre-flight check."
  type        = string
}

variable "vm_size" {
  description = "VM size for both spoke VMs. Chosen from the VM pre-flight check."
  type        = string
}

variable "admin_username" {
  type    = string
  default = "labadmin"
}

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "tags" {
  type    = map(string)
  default = { lab = "network-security" }
}
