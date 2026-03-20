module "namespaces" {
  source = "./modules/namespaces"
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
