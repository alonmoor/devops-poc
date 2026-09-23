terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.31" }
    vault      = { source = "hashicorp/vault", version = "~> 4.4" }
  }
  backend "local" {
    path = "terraform-prod.tfstate"
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kubernetes-admin@kubernetes"
}

provider "vault" {
  address = "http://127.0.0.1:8200"
}

module "catalog_namespace" {
  source      = "../../modules/namespace"
  environment = "prod"
  namespace   = "catalog-prod"
  team_group  = "team-platform-oncall" # NOT the app team - prod RBAC goes to on-call/platform only

  resource_quota = {
    requests_cpu    = "8"
    requests_memory = "16Gi"
    limits_cpu      = "16"
    limits_memory   = "32Gi"
    pods            = 50
  }
}

module "orders_namespace" {
  source      = "../../modules/namespace"
  environment = "prod"
  namespace   = "orders-prod"
  team_group  = "team-platform-oncall"

  resource_quota = {
    requests_cpu    = "8"
    requests_memory = "16Gi"
    limits_cpu      = "16"
    limits_memory   = "32Gi"
    pods            = 50
  }
}

module "demo_namespace" {
  source                = "../../modules/namespace"
  environment           = "prod"
  namespace             = "demo-prod"
  team_group            = "team-platform-oncall"
  # local-path-provisioner (this cluster's default StorageClass) doesn't
  # honor fsGroup, so demo-postgres needs a root initContainer to chown
  # its volume on first boot - incompatible with "restricted" PSA.
  # Relaxed to "baseline" for this namespace only; every other prod
  # namespace (catalog-prod, orders-prod) stays "restricted".
  psa_enforce_override  = "baseline"

  resource_quota = {
    requests_cpu    = "4"
    requests_memory = "8Gi"
    limits_cpu      = "8"
    limits_memory   = "16Gi"
    pods            = 30
  }
}
