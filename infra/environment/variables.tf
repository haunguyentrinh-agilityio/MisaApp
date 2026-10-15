variable "environment" {
  description = "Deployment environment: develop, stage or production."
  type        = string

  validation {
    condition     = contains(["develop", "stage", "production"], var.environment)
    error_message = "environment must be develop, stage or production."
  }
}

variable "location" {
  description = "Azure region, e.g. southeastasia."
  type        = string
}

variable "suffix" {
  description = "Global-uniqueness suffix for SQL server and Key Vault names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{1,6}$", var.suffix))
    error_message = "suffix must be 1-6 lower-case letters or digits."
  }
}

variable "image_tag" {
  description = "Full git commit SHA of the images to run (misaapp-api, misaapp-web, misaapp-migrator)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.image_tag))
    error_message = "image_tag must be a 40-character lower-case commit SHA."
  }
}

variable "acr_name" {
  description = "Name of the shared container registry in rg-misaapp-shared."
  type        = string
}

variable "sql_sku" {
  description = "Database SKU, e.g. GP_S_Gen5_1 (serverless) or S0."
  type        = string
}

variable "sql_auto_pause_minutes" {
  description = "Serverless auto-pause delay in minutes; -1 disables. Ignored for non-serverless SKUs."
  type        = number
  default     = -1
}

variable "sql_use_free_offer" {
  description = "Create the database with the Azure SQL free offer. Only takes effect at creation; flipping it replaces the database."
  type        = bool
  default     = false
}

variable "web_min_replicas" {
  description = "Minimum replicas of the web app."
  type        = number
}

variable "web_max_replicas" {
  description = "Maximum replicas of the web app."
  type        = number
}

variable "api_min_replicas" {
  description = "Minimum replicas of the API app."
  type        = number
}

variable "api_max_replicas" {
  description = "Maximum replicas of the API app."
  type        = number
}

variable "gemini_enabled" {
  description = "Map Key Vault secret gemini-api-key to Gemini__ApiKey. When false the API uses its echo model."
  type        = bool
}

variable "gemini_model" {
  description = "Gemini model name."
  type        = string
  default     = "gemini-3.8-flash"
}

variable "log_retention_days" {
  description = "Log Analytics retention in days."
  type        = number
  default     = 30
}
