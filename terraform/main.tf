module "namespaces" {
  source = "./modules/namespaces"
}

module "observability" {
  source = "./modules/observability"

  namespace              = module.namespaces.namespace_names["observability"]
  grafana_admin_password = var.grafana_admin_password
  db_name                = var.db_name
  db_user                = var.db_user
  db_password            = var.db_password

  depends_on = [module.namespaces]
}

module "database" {
  source = "./modules/database"

  namespace     = module.namespaces.namespace_names["database"]
  db_name       = var.db_name
  db_user       = var.db_user
  db_password   = var.db_password
  chart_version = var.chart_version != null ? var.chart_version : "17.1.0"

  depends_on = [module.namespaces]
}

module "apps" {
  source = "./modules/apps"

  namespace = module.namespaces.namespace_names["apps"]

  depends_on = [module.namespaces]
}

module "aiops" {
  source = "./modules/aiops"

  namespace         = module.namespaces.namespace_names["aiops"]
  claude_api_key    = var.claude_api_key
  github_token      = var.github_token
  github_repo       = var.github_repo
  database_url      = "postgresql://${var.db_user}:${var.db_password}@${module.database.service_endpoint}/${var.db_name}"
  loki_url          = module.observability.loki_endpoint
  slack_webhook_url = var.slack_webhook_url

  depends_on = [module.namespaces, module.database, module.observability]
}

module "cryptoflux" {
  source = "./modules/cryptoflux"

  namespace = module.namespaces.namespace_names["cryptoflux"]

  cf_db_name   = var.cf_db_name
  cf_db_user   = var.cf_db_user
  cf_db_pass   = var.cf_db_pass

  cf_dr_db_name = var.cf_dr_db_name
  cf_dr_db_user = var.cf_dr_db_user
  cf_dr_db_pass = var.cf_dr_db_pass

  cf_secret_key           = var.cf_secret_key
  cf_trading_data_api_key = var.cf_trading_data_api_key
  cf_ext_api_key          = var.cf_ext_api_key

  cf_interval_seconds      = var.cf_interval_seconds
  cf_batch_size            = var.cf_batch_size
  cf_retention_days        = var.cf_retention_days
  cf_sync_interval_seconds = var.cf_sync_interval_seconds

  depends_on = [module.namespaces]
}
