output "namespace" {
  value = kubernetes_namespace.this.metadata[0].name
}

output "vault_role_name" {
  value = vault_kubernetes_auth_backend_role.this.role_name
}
