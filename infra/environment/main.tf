# Names for one environment, kept in one place.
locals {
  env_code = { develop = "dev", stage = "stg", production = "prd" }[var.environment]

  resource_group_name    = "rg-misaapp-${var.environment}"
  web_app_name           = "ca-misaapp-${var.environment}-web"
  api_app_name           = "ca-misaapp-${var.environment}-api"
  migrate_job_name       = "caj-misaapp-${var.environment}-migrate"
  sql_server_name        = "sql-misaapp-${var.environment}-${var.suffix}"
  sql_database_name      = "sqldb-misaapp"
  key_vault_name         = "kv-misaapp-${local.env_code}-${var.suffix}" # Key Vault names are limited to 24 characters
  api_identity_name      = "id-misaapp-${var.environment}-api"
  web_identity_name      = "id-misaapp-${var.environment}-web"
  migrator_identity_name = "id-misaapp-${var.environment}-migrator"
  acr_login_server       = data.azurerm_container_registry.shared.login_server
  serverless_sql         = startswith(var.sql_sku, "GP_S_")

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
