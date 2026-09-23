variable "environment" {
  description = "dev | staging | prod - drives every policy difference below"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of dev, staging, prod."
  }
}

variable "namespace" {
  description = "Kubernetes namespace name, e.g. catalog-dev"
  type        = string
}

variable "team_group" {
  description = "IdP group (e.g. Okta/Azure AD group) that gets namespace-scoped RBAC access"
  type        = string
}

variable "resource_quota" {
  description = "Per-environment compute ceiling for the namespace"
  type = object({
    requests_cpu    = string
    requests_memory = string
    limits_cpu      = string
    limits_memory   = string
    pods            = number
  })
}

variable "vault_kubernetes_backend_path" {
  description = "Path where Vault's Kubernetes auth method is mounted for this cluster"
  type        = string
  default     = "kubernetes"
}

variable "psa_enforce_override" {
  description = "Override the environment-derived PodSecurity enforce level (baseline/restricted/privileged). Leave null for the normal dev/staging=baseline, prod=restricted rule."
  type        = string
  default     = null
}
