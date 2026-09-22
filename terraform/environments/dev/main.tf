terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.31" }
    vault      = { source = "hashicorp/vault", version = "~> 4.4" }
  }
  # WORKING ASSUMPTION: remote state backend (S3+DynamoDB, or Terraform
  # Cloud) configured per-environment here; omitted from this POC snippet
  # since the bucket/table names are org-specific and out of scope.
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kubernetes-admin@kubernetes"
  # WORKING ASSUMPTION: single shared cluster with per-env namespaces here
  # (context stays the same across dev/staging/prod). If the org instead
  # chooses separate clusters per environment (see docs/DECISIONS.md -
  # "Namespaces vs separate clusters"), only config_context changes here;
  # every other resource in the module is identical.
}

provider "vault" {
  address = "http://127.0.0.1:8200"
}

module "catalog_namespace" {
  source      = "../../modules/namespace"
  environment = "dev"
  namespace   = "catalog-dev"
  team_group  = "team-catalog-devs" # broadest group - includes all devs on the team

  resource_quota = {
    requests_cpu    = "2"
    requests_memory = "4Gi"
    limits_cpu      = "4"
    limits_memory   = "8Gi"
    pods            = 20
  }
}

module "orders_namespace" {
  source      = "../../modules/namespace"
  environment = "dev"
  namespace   = "orders-dev"
  team_group  = "team-orders-devs"

  resource_quota = {
    requests_cpu    = "2"
    requests_memory = "4Gi"
    limits_cpu      = "4"
    limits_memory   = "8Gi"
    pods            = 20
  }
}
