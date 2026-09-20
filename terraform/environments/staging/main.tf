terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.31" }
    vault      = { source = "hashicorp/vault", version = "~> 4.4" }
  }
  backend "s3" {
    bucket = "devops-poc-tfstate"
    key    = "staging/namespace.tfstate"
    region = "eu-west-1"
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "staging-cluster"
}

provider "vault" {
  address = "https://vault.internal.example.com"
}

module "catalog_namespace" {
  source      = "../../modules/namespace"
  environment = "staging"
  namespace   = "catalog-staging"
  team_group  = "team-catalog-leads" # narrower group than dev - leads only

  resource_quota = {
    requests_cpu    = "4"
    requests_memory = "8Gi"
    limits_cpu      = "8"
    limits_memory   = "16Gi"
    pods            = 30
  }
}

module "orders_namespace" {
  source      = "../../modules/namespace"
  environment = "staging"
  namespace   = "orders-staging"
  team_group  = "team-orders-leads"

  resource_quota = {
    requests_cpu    = "4"
    requests_memory = "8Gi"
    limits_cpu      = "8"
    limits_memory   = "16Gi"
    pods            = 30
  }
}
