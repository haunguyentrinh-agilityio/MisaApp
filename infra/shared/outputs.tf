output "acr_login_server" {
  description = "Login server of the shared registry, e.g. crmisaappabc123.azurecr.io."
  value       = azurerm_container_registry.main.login_server
}
