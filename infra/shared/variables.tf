variable "location" {
  description = "Azure region for the shared resources, e.g. southeastasia."
  type        = string
}

variable "suffix" {
  description = "Global-uniqueness suffix for the shared registry name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{1,6}$", var.suffix))
    error_message = "suffix must be 1-6 lower-case letters or digits."
  }
}

variable "ci_principal_id" {
  description = "Object (principal) ID of the id-misaapp-gh-ci identity used by PR checks."
  type        = string
}
