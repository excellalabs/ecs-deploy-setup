# ecs-cli uses CloudFormation to create resources. 

ecs-cli configure --region us-east-1 --cluster web-apps --profile default

ecs-cli up --vpc vpc-fef93e99 --subnets subnet-b54329d0,subnet-a3583089 --keypair api-sample-ecs-cluster --instance-type t2.micro --size=1 --port 80 --capability-iam
#--security-group id 

# Load balancer 