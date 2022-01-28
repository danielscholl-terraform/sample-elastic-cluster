variable "naming_rules" {
  description = "naming conventions yaml file"
  type        = string
}

variable "environment" {
  description = "oak.environment (./modules/naming-rules#customenvironment)"
  type        = string
}

variable "location" {
  description = "oak.azureRegion (./modules/naming-rules#customazureregion)"
  type        = string
}


# Optional tags
variable "product" {
  description = "oak.productGroup (./modules/naming-rules#customproductgroup) or [a-z0-9]{2,12}"
  type        = string
  default     = ""

  validation {
    condition     = length(regexall("[a-z0-9]{2,12}", var.product)) == 1
    error_message = "ERROR: product must [a-z0-9]{2,12}."
  }
}

# Optional free-form tags
variable "additional_tags" {
  type        = map(string)
  description = "A map of additional tags to add to the tags output"
  default     = {}
}
