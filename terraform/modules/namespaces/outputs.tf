output "namespace_names" {
  description = "Map of namespace key to namespace name, for use as module.namespaces.namespace_names[\"database\"] etc."
  value       = { for k, v in kubernetes_namespace.this : k => v.metadata[0].name }
}
