provider "azurerm" {
  features {}
  use_oidc            = true
  storage_use_azuread = true
  # Deploy identities only hold resource-group roles; bootstrap.sh registers the providers once.
  resource_provider_registrations = "none"
}

provider "azapi" {
  use_oidc = true
}
