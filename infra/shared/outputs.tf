output "acr_login_server" {
  description = "Login server of the shared registry, e.g. crmisaappabc123.azurecr.io."
  value       = azurerm_container_registry.main.login_server
}

output "nonprod_sql_fqdn" {
  description = "FQDN of the nonprod SQL server (developer and CI databases)."
  value       = azurerm_mssql_server.nonprod.fully_qualified_domain_name
}

output "nonprod_key_vault_name" {
  description = "Key Vault holding sql-admin-password for the nonprod server."
  value       = azurerm_key_vault.nonprod.name
}
