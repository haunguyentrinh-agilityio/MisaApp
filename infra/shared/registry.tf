resource "azurerm_container_registry" "main" {
  name                = "crmisaapp${var.suffix}"
  resource_group_name = data.azurerm_resource_group.shared.name
  location            = var.location
  sku                 = "Standard"
  admin_enabled       = false
  tags                = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

# CI E2E pulls the images the deploy run's build job pushed.
resource "azurerm_role_assignment" "ci_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = var.ci_principal_id
  principal_type       = "ServicePrincipal"
}
