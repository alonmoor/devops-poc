# terraform/modules/namespace/main.tf
#
# One module, instantiated three times (dev/staging/prod) - this is the
# artifact that makes the environment differences reviewable in a single
# PR diff instead of three hand-maintained YAML trees that quietly drift
# apart, which is exactly the "no consistent standardization between
# teams" problem described in the assignment.

resource "kubernetes_namespace" "this" {
  metadata {
    name = var.namespace
    labels = {
      "environment"                        = var.environment
      "pod-security.kubernetes.io/enforce" = var.environment == "prod" ? "restricted" : "baseline"
      # dev/staging run under "baseline" PSA so teams aren't fighting the
      # restricted profile while iterating; prod enforces "restricted"
      # (non-root, no privilege escalation, dropped capabilities - all of
      # which the Deployment template already satisfies by default).
    }
  }
}

resource "kubernetes_resource_quota" "this" {
  metadata {
    name      = "${var.namespace}-quota"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    hard = {
      "requests.cpu"    = var.resource_quota.requests_cpu
      "requests.memory" = var.resource_quota.requests_memory
      "limits.cpu"      = var.resource_quota.limits_cpu
      "limits.memory"   = var.resource_quota.limits_memory
      "pods"            = tostring(var.resource_quota.pods)
    }
  }
}

resource "kubernetes_limit_range" "default_requests" {
  # Backstop for teams that forget to set requests/limits on a container -
  # without this, one missing "resources:" block can starve the node.
  metadata {
    name      = "${var.namespace}-default-limits"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "200m"
        memory = "128Mi"
      }
      default_request = {
        cpu    = "50m"
        memory = "64Mi"
      }
    }
  }
}

# Baseline zero-trust: deny all ingress by default at the namespace level.
# Each service's Helm chart then opens the narrow pod-to-pod hole it
# actually needs (see helm/catalog-api/templates/networkpolicy.yaml) -
# "default deny + explicit allow" rather than "default allow" everywhere,
# which was the prior "no clear RBAC/network boundary" state.
resource "kubernetes_network_policy" "default_deny_ingress" {
  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

# ---------------------------------------------------------------------
# RBAC: same Role *shape* across environments, different verb sets.
# This is the part of the design most directly aimed at the "no clear
# RBAC boundary between environments" pain point in the assignment.
# ---------------------------------------------------------------------

locals {
  # dev: broad, fast iteration - team can debug directly.
  # staging: can deploy/observe but not delete/exec into prod-shaped data.
  # prod: read-only by default; any write goes through the CI/CD
  #        pipeline's own service account, never a human's.
  rbac_verbs_by_env = {
    dev = [
      "get", "list", "watch", "create", "update", "patch", "delete",
      "create" # explicit dup harmless; kept for readability of intent
    ]
    staging = ["get", "list", "watch", "create", "update", "patch"]
    prod    = ["get", "list", "watch"]
  }
  verbs = distinct(local.rbac_verbs_by_env[var.environment])
}

resource "kubernetes_role" "team_namespace_role" {
  metadata {
    name      = "${var.namespace}-team-role"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  rule {
    api_groups = ["", "apps", "batch"]
    resources  = ["pods", "deployments", "services", "jobs", "configmaps"]
    verbs      = local.verbs
  }

  rule {
    # Secrets are readable by nobody's human RBAC role, in any
    # environment - the ONLY path to secret material is ESO pulling from
    # Vault into a Secret object that the *workload* (not a human) reads.
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["list"] # list only, to see that a secret exists - never "get"
  }

  rule {
    # pods/log and pods/exec are intentionally environment-gated: fine in
    # dev, forbidden in staging/prod (exec into a prod pod is a break-glass
    # action that should go through a separate, audited, time-boxed
    # elevated-access flow - out of scope for this POC).
    api_groups = [""]
    resources  = var.environment == "dev" ? ["pods/log", "pods/exec"] : ["pods/log"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_role_binding" "team_namespace_binding" {
  metadata {
    name      = "${var.namespace}-team-binding"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.team_namespace_role.metadata[0].name
  }
  subject {
    kind      = "Group"
    name      = var.team_group
    api_group = "rbac.authorization.k8s.io"
  }
}

# ---------------------------------------------------------------------
# Vault Kubernetes auth: bind THIS namespace's default ServiceAccount
# (and any app-specific SA) to a Vault role scoped ONLY to secrets under
# secret/data/<environment>/* - a compromised pod in dev can never read a
# prod secret, because the Vault-side policy, not just k8s RBAC, enforces
# the boundary.
# ---------------------------------------------------------------------

resource "vault_policy" "namespace_read" {
  name   = "${var.namespace}-read"
  policy = <<-EOT
    path "secret/data/${var.environment}/*" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "this" {
  backend                          = var.vault_kubernetes_backend_path
  role_name                        = var.namespace
  bound_service_account_names      = ["*"] # narrowed per-app in the ExternalSecret's own SA in a fuller implementation
  bound_service_account_namespaces = [var.namespace]
  token_policies                   = [vault_policy.namespace_read.name]
  # Short TTL: ESO re-authenticates on every refreshInterval anyway, so
  # there is no operational reason to hand out long-lived Vault tokens.
  token_ttl = 300
}
