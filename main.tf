module "network" {
  source = "./modules/network"
  region = var.region
}

module "iam" {
  source = "./modules/iam"
}
