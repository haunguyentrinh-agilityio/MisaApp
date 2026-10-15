# Nonprod server: per-developer databases and ephemeral CI databases (sqldb-misaapp-ci-*, created
# and dropped by infra/scripts/ci-database.sh). SQL auth, because the Docker stack can't use an
# Entra token. No "Allow Azure services" rule: developers and CI add their own IP rules.

resource "random_password" "sql_admin" {
  length           = 32
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!#%*+-=?@^_" # no ; ' " so it is safe inside a connection string
}

resource "azurerm_mssql_server" "nonprod" {
  name                          = "sql-misaapp-nonprod-${var.suffix}"
  resource_group_name           = data.azurerm_resource_group.shared.name
  location                      = var.location
  version                       = "12.0"
  administrator_login           = "misaappadmin"
  administrator_login_password  = random_password.sql_admin.result
  minimum_tls_version           = "1.2"
  public_network_access_enabled = true
  tags                          = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

# The free offer can only be chosen when a database is created (it can't be applied to an existing
# one), and azurerm has no useFreeLimit argument, so these are created through the ARM API.
# Up to 10 free databases per subscription, all in one region.
resource "azapi_resource" "developer_database" {
  for_each = toset(var.developers)

  type      = "Microsoft.Sql/servers/databases@2023-08-01"
  name      = "sqldb-misaapp-dev-${each.key}"
  parent_id = azurerm_mssql_server.nonprod.id
  location  = var.location
  tags      = local.tags

  body = {
    sku = {
      name     = "GP_S_Gen5"
      tier     = "GeneralPurpose"
      family   = "Gen5"
      capacity = 1
    }
    properties = {
      autoPauseDelay              = 60
      minCapacity                 = 0.5
      maxSizeBytes                = 34359738368 # 32 GB, the free-offer limit
      useFreeLimit                = true
      freeLimitExhaustionBehavior = "AutoPause"
    }
  }
}

# CI creates/drops its databases and its runner firewall rule.
resource "azurerm_role_assignment" "ci_sql_db_contributor" {
  scope                = azurerm_mssql_server.nonprod.id
  role_definition_name = "SQL DB Contributor"
  principal_id         = var.ci_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "ci_sql_server_contributor" {
  scope                = azurerm_mssql_server.nonprod.id
  role_definition_name = "SQL Server Contributor"
  principal_id         = var.ci_principal_id
  principal_type       = "ServicePrincipal"
}
