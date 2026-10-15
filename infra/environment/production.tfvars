# suffix, acr_name and image_tag come from -var in deploy.yml.
# gemini_enabled: deploy.yml checks that gemini-api-key exists in kv-misaapp-prd-<suffix> first.
environment            = "production"
location               = "southeastasia"
sql_sku                = "S0"
sql_auto_pause_minutes = -1
sql_use_free_offer     = false
web_min_replicas       = 1
web_max_replicas       = 5
api_min_replicas       = 1
api_max_replicas       = 5
gemini_enabled         = true
