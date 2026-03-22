locals {
  namespaces = ["observability", "database", "apps", "aiops", "chaos", "cryptoflux"]
}

resource "kubernetes_namespace" "this" {
  for_each = toset(local.namespaces)

  metadata {
    name = each.key
    labels = {
      "managed-by" = "terraform"
    }
  }
}
