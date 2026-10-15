provider "azurerm" {
  features {}
  use_oidc            = true
  storage_use_azuread = true
  # Deploy identities only hold resource-group roles; bootstrap.sh registers the providers once.
  resource_provider_registrations = "none"
}

# Free-offer database (sql_use_free_offer): the offer can only be set at creation through the ARM API.
provider "azapi" {
  use_oidc = true
}
