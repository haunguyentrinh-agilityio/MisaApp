# Entra-only server: the migrator identity is its admin and creates the API identity's user
# (backend/deploy/migrate.sh). No SQL logins, so there is no password to store.
resource "azurerm_mssql_server" "main" {
  name                          = local.sql_server_name
  resource_group_name           = data.azurerm_resource_group.env.name
  location                      = var.location
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = true
  tags                          = local.tags

  azuread_administrator {
    login_username              = azurerm_user_assigned_identity.migrator.name
    object_id                   = azurerm_user_assigned_identity.migrator.principal_id
    tenant_id                   = data.azurerm_client_config.current.tenant_id
    azuread_authentication_only = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Consumption Container Apps have no fixed egress IPs or VNet, so the apps reach SQL through
# "Allow Azure services". Logins still need an Entra token for one of this environment's identities.
resource "azurerm_mssql_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Exactly one of the two database resources exists. The free offer can only be chosen at creation,
# so flipping sql_use_free_offer replaces the database; prevent_destroy blocks that by design.
resource "azurerm_mssql_database" "main" {
  count = var.sql_use_free_offer ? 0 : 1

  name                        = local.sql_database_name
  server_id                   = azurerm_mssql_server.main.id
  sku_name                    = var.sql_sku
  auto_pause_delay_in_minutes = local.serverless_sql ? var.sql_auto_pause_minutes : null
  min_capacity                = local.serverless_sql ? 0.5 : null
  tags                        = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azapi_resource" "free_database" {
  count = var.sql_use_free_offer ? 1 : 0

  type      = "Microsoft.Sql/servers/databases@2023-08-01"
  name      = local.sql_database_name
  parent_id = azurerm_mssql_server.main.id
  location  = var.location
  tags      = local.tags

  body = {
    sku = {
      name     = "GP_S_Gen5"
      tier     = "GeneralPurpose"
      family   = "Gen5"
      capacity = tonumber(trimprefix(var.sql_sku, "GP_S_Gen5_"))
    }
    properties = {
      autoPauseDelay              = var.sql_auto_pause_minutes
      minCapacity                 = 0.5
      maxSizeBytes                = 34359738368 # 32 GB, the free-offer limit
      useFreeLimit                = true
      freeLimitExhaustionBehavior = "AutoPause"
    }
  }

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = can(regex("^GP_S_Gen5_[0-9]+$", var.sql_sku))
      error_message = "sql_use_free_offer needs a serverless SKU (GP_S_Gen5_<vCores>)."
    }
  }
}
