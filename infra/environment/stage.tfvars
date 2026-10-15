# suffix, acr_name and image_tag come from -var in deploy.yml.
environment            = "stage"
location               = "southeastasia"
sql_sku                = "GP_S_Gen5_1"
sql_auto_pause_minutes = 60
sql_use_free_offer     = false
web_min_replicas       = 0
web_max_replicas       = 2
api_min_replicas       = 0
api_max_replicas       = 2
gemini_enabled         = false
