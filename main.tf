module "network" {
  source = "./modules/network"
  region = var.region
}

module "iam" {
  source = "./modules/iam"
}

module "agent" {
  source            = "./modules/agent"
  vpc_id            = module.network.vpc_id
  subnet_ids        = module.network.private_subnet_ids
  s3_prefix_list_id = module.network.s3_prefix_list_id
  role_arn          = module.iam.agent_role_arn
  inbox_bucket      = module.iam.inbox_bucket
  secret_bucket     = module.iam.secret_bucket
}

module "detection" {
  source          = "./modules/detection"
  agent_role_name = module.iam.agent_role_name
  agent_role_arn  = module.iam.agent_role_arn
  alarm_name      = module.agent.alarm_name
}
