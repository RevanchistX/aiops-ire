module "namespaces" {
  source = "./modules/namespaces"
}

module "observability" {
  source = "./modules/observability"

  namespace              = module.namespaces.namespace_names["observability"]
  grafana_admin_password = var.grafana_admin_password

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

  namespace      = module.namespaces.namespace_names["aiops"]
  claude_api_key = var.claude_api_key
  github_token   = var.github_token
  github_repo    = var.github_repo
  database_url   = "postgresql://${var.db_user}:${var.db_password}@${module.database.service_endpoint}/${var.db_name}"
  loki_url       = module.observability.loki_endpoint

  depends_on = [module.namespaces, module.database, module.observability]
}
