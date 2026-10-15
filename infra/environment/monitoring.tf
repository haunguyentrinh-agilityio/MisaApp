resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-misaapp-${var.environment}"
  resource_group_name = data.azurerm_resource_group.env.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}
