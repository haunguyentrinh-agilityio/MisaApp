resource "azurerm_container_app_environment" "main" {
  name                       = "cae-misaapp-${var.environment}"
  resource_group_name        = data.azurerm_resource_group.env.name
  location                   = var.location
  logs_destination           = "log-analytics"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = local.tags
}

# Zero-downtime rollout (FR-013): Single revision mode only shifts traffic once the new revision is
# ready, and the old replicas get 30 s to finish in-flight requests.
resource "azurerm_container_app" "api" {
  name                         = local.api_app_name
  resource_group_name          = data.azurerm_resource_group.env.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  revision_mode                = "Single"
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.api.id]
  }

  registry {
    server   = local.acr_login_server
    identity = azurerm_user_assigned_identity.api.id
  }

  dynamic "secret" {
    for_each = var.gemini_enabled ? [1] : []
    content {
      name                = "gemini-api-key"
      key_vault_secret_id = "${azurerm_key_vault.main.vault_uri}secrets/gemini-api-key"
      identity            = azurerm_user_assigned_identity.api.id
    }
  }

  # Internal: only the web app reaches the API, over the environment's plain-HTTP network.
  ingress {
    external_enabled           = false
    target_port                = 8080
    allow_insecure_connections = true

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas                     = var.api_min_replicas
    max_replicas                     = var.api_max_replicas
    termination_grace_period_seconds = 30

    container {
      name   = "api"
      image  = "${local.acr_login_server}/misaapp-api:${var.image_tag}"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "ASPNETCORE_ENVIRONMENT"
        value = "Production"
      }
      env {
        name  = "ConnectionStrings__Default"
        value = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Database=${local.sql_database_name};Authentication=Active Directory Managed Identity;User Id=${azurerm_user_assigned_identity.api.client_id};Encrypt=True"
      }
      env {
        name  = "Database__MigrateOnStartup"
        value = "false"
      }
      env {
        name  = "Gemini__Model"
        value = var.gemini_model
      }
      env {
        name  = "App__Environment"
        value = var.environment
      }
      dynamic "env" {
        for_each = var.gemini_enabled ? [1] : []
        content {
          name        = "Gemini__ApiKey"
          secret_name = "gemini-api-key"
        }
      }

      # /api/health includes the database; a paused serverless database takes up to a minute to
      # resume, so startup tolerates about 120 s.
      startup_probe {
        transport               = "HTTP"
        path                    = "/api/health"
        port                    = 8080
        interval_seconds        = 12
        failure_count_threshold = 10
      }

      readiness_probe {
        transport               = "HTTP"
        path                    = "/api/health"
        port                    = 8080
        initial_delay           = 5
        interval_seconds        = 5
        failure_count_threshold = 3
      }

      liveness_probe {
        transport               = "HTTP"
        path                    = "/api/health"
        port                    = 8080
        failure_count_threshold = 5
      }
    }
  }

  depends_on = [azurerm_role_assignment.acr_pull, azurerm_role_assignment.api_kv_secrets_user]
}

resource "azurerm_container_app" "web" {
  name                         = local.web_app_name
  resource_group_name          = data.azurerm_resource_group.env.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  revision_mode                = "Single"
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.web.id]
  }

  registry {
    server   = local.acr_login_server
    identity = azurerm_user_assigned_identity.web.id
  }

  ingress {
    external_enabled           = true
    target_port                = 80
    allow_insecure_connections = false

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas                     = var.web_min_replicas
    max_replicas                     = var.web_max_replicas
    termination_grace_period_seconds = 30

    container {
      name   = "web"
      image  = "${local.acr_login_server}/misaapp-web:${var.image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "API_UPSTREAM"
        value = "http://${local.api_app_name}"
      }
      env {
        name  = "NGINX_ENTRYPOINT_LOCAL_RESOLVERS"
        value = "1"
      }

      readiness_probe {
        transport               = "HTTP"
        path                    = "/"
        port                    = 80
        initial_delay           = 5
        interval_seconds        = 5
        failure_count_threshold = 3
      }
    }
  }

  depends_on = [azurerm_role_assignment.acr_pull]
}
