output "web_url" {
  description = "Public URL of the web app (GitHub environment URL, smoke-test BASE_URL)."
  value       = "https://${azurerm_container_app.web.ingress[0].fqdn}"
}

output "image_tag" {
  description = "Commit SHA the API app runs; deploy.yml reads it as the rollback target. Absent until the apps exist (first deployment)."
  value       = trimprefix(azurerm_container_app.api.template[0].container[0].image, "${local.acr_login_server}/misaapp-api:")
}

output "migrate_job_name" {
  description = "Container Apps job that applies EF Core migrations."
  value       = azurerm_container_app_job.migrate.name
}

output "resource_group_name" {
  description = "Resource group of this environment."
  value       = data.azurerm_resource_group.env.name
}

output "key_vault_name" {
  description = "Key Vault holding this environment's secrets (gemini-api-key)."
  value       = azurerm_key_vault.main.name
}

output "sql_server_fqdn" {
  description = "Fully qualified name of this environment's SQL server."
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}
