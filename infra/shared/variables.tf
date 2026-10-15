variable "location" {
  description = "Azure region for the shared resources, e.g. southeastasia."
  type        = string
}

variable "suffix" {
  description = "Global-uniqueness suffix for registry, SQL server and Key Vault names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{1,6}$", var.suffix))
    error_message = "suffix must be 1-6 lower-case letters or digits."
  }
}

variable "developers" {
  description = "Developer aliases; each gets a free-offer database sqldb-misaapp-dev-<alias>."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for alias in var.developers : can(regex("^[a-z0-9]{2,12}$", alias))])
    error_message = "Each developer alias must be 2-12 lower-case letters or digits."
  }
}

variable "ci_principal_id" {
  description = "Object (principal) ID of the id-misaapp-gh-ci identity used by PR checks."
  type        = string
}
