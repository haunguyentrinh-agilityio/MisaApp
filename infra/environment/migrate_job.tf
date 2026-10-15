# Runs backend/deploy/migrate.sh. deploy.yml starts one execution per deploy with
# `az containerapp job start --image …misaapp-migrator:<sha>` before the apps are updated, so a
# failed migration leaves the previous revision serving.
resource "azurerm_container_app_job" "migrate" {
  name                         = local.migrate_job_name
  resource_group_name          = data.azurerm_resource_group.env.name
  location                     = var.location
  container_app_environment_id = azurerm_container_app_environment.main.id
  replica_timeout_in_seconds   = 600
  replica_retry_limit          = 0
  tags                         = local.tags

  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.migrator.id]
  }

  registry {
    server   = local.acr_login_server
    identity = azurerm_user_assigned_identity.migrator.id
  }

  template {
    container {
      name   = "migrate"
      image  = "${local.acr_login_server}/misaapp-migrator:${var.image_tag}"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "SQL_SERVER"
        value = azurerm_mssql_server.main.fully_qualified_domain_name
      }
      env {
        name  = "SQL_DATABASE"
        value = local.sql_database_name
      }
      env {
        name  = "MIGRATOR_CLIENT_ID"
        value = azurerm_user_assigned_identity.migrator.client_id
      }
      env {
        name  = "APP_IDENTITY_NAME"
        value = azurerm_user_assigned_identity.api.name
      }
      env {
        name  = "APP_CLIENT_ID"
        value = azurerm_user_assigned_identity.api.client_id
      }
    }
  }

  # The first deploy applies only this job and the database (-target), runs the migration, then
  # applies the rest. Depending on every role assignment here creates them in that first step, so
  # they have propagated by the time the apps pull images and read Key Vault.
  depends_on = [
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.api_kv_secrets_user,
    azurerm_mssql_firewall_rule.azure_services,
    azurerm_mssql_database.main,
    azapi_resource.free_database,
  ]
}
