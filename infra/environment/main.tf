# Names for one environment, kept in one place.
locals {
  env_code = { develop = "dev", stage = "stg", production = "prd" }[var.environment]

  resource_group_name = "rg-misaapp-${var.environment}"
  web_app_name        = "ca-misaapp-${var.environment}-web"
  api_app_name        = "ca-misaapp-${var.environment}-api"
  key_vault_name      = "kv-misaapp-${local.env_code}-${var.suffix}" # Key Vault names are limited to 24 characters
  api_identity_name   = "id-misaapp-${var.environment}-api"
  web_identity_name   = "id-misaapp-${var.environment}-web"
  acr_login_server    = data.azurerm_container_registry.shared.login_server

  tags = {
    app         = "misaapp"
    environment = var.environment
  }
}

# Created by infra/bootstrap/bootstrap.sh; the deploy identity only holds roles on this group.
data "azurerm_resource_group" "env" {
  name = local.resource_group_name
}

data "azurerm_container_registry" "shared" {
  name                = var.acr_name
  resource_group_name = "rg-misaapp-shared"
}

data "azurerm_client_config" "current" {}
