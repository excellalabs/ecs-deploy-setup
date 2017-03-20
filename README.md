# Deploying a container-based app to ECS via CI

Sample that covers deploying a container-based app to ECS via CI (including IAM account setup)

## ECS Deployment Process Overview

### One-time setup

Here we'll go through setting up an ECS cluster, deploying a container-based app to it, and automating the process with a CI tool (TravisCI in this case).

This process includes creating an ECS cluster (or using an existing one), creating a ECS container registry(s) (ECR) for an app (app assumed to be already developed; a sample is used in this repo from Docker Hub), preparing ECS task definition files that deploy and run our app instances in ECS (from ECR), and creating ECS services for the task definitions to make sure the app stays running and is easily updated.

Then, we'll set up a cloud-based CI tool to deploy the app based on check-ins to branches in a VCS. A particular branch (i.e. master, staging, production) will be pushed to, and the CI tool will rebuild the app image, run tests, and push it into the container regiesty (ECR). Then the CI tool will create a revision of the ECS task deinition, and trigger the ECS service to update and redeploy the app based on the task definition. 

### On each deploy

Once everything is set up, here is what 

- A deployment triggered by push to a VCS branch. CI builds images for app, runs tests, and pushes a new image version to the container registry. 
- ecs-deploy.sh creates a new revision of our task definition, for the new version of our app. Each revision only differs by the image tag we specify. We update the task family with the new task revision.
- ecs-deploy updates the running service to use the new task definition revision. Based on how the service was configured, it will smartly stop & start task to update everything to the newest revision. Once the script sees the new task definition running, it’s considered a success and ends.

## *Part 1.* Setting up IAM accounts for ECS management and deployment

IAM accounts are needed to *create/setup ECS*, and to *deploy the application*.  

Steps: 

1. **Create an IAM group user with permission to manage ECS** - create a user and put in a new group called `ecsAdmins`, with these policies:
    - AmazonEC2ContainerServiceFullAccess
    - AWSCertificateManagerFullAccess
    - AmazonRoute53FullAccess
    - New policy called `EC2ContainerServiceAdministration` with these permissions - all operations around ECS that are needed to set it up for an app (i.e. creating the initial service, load balancers):

        ```json
        {
            "Version": "2012-10-17",
            "Statement": [
                  {
                  "Effect": "Allow",
                  "Action": [
                      "autoscaling:CreateAutoScalingGroup",
                      "autoscaling:CreateLaunchConfiguration",
                      "autoscaling:CreateOrUpdateTags",
                      "autoscaling:DeleteAutoScalingGroup",
                      "autoscaling:DeleteLaunchConfiguration",
                      "autoscaling:DescribeAutoScalingGroups",
                      "autoscaling:DescribeAutoScalingInstances",
                      "autoscaling:DescribeAutoScalingNotificationTypes",
                      "autoscaling:DescribeLaunchConfigurations",
                      "autoscaling:DescribeScalingActivities",
                      "autoscaling:DescribeTags",
                      "autoscaling:DescribeTriggers",
                      "autoscaling:UpdateAutoScalingGroup",
                      "cloudformation:CreateStack",
                      "cloudformation:DescribeStack*",
                      "cloudformation:DeleteStack",
                      "cloudformation:UpdateStack",
                      "cloudwatch:GetMetricStatistics",
                      "cloudwatch:ListMetrics",
                      "ec2:AssociateRouteTable",
                      "ec2:AttachInternetGateway",
                      "ec2:AuthorizeSecurityGroupIngress",
                      "ec2:CreateInternetGateway",
                      "ec2:CreateKeyPair",
                      "ec2:CreateNetworkInterface",
                      "ec2:CreateRoute",
                      "ec2:CreateRouteTable",
                      "ec2:CreateSecurityGroup",
                      "ec2:CreateSubnet",
                      "ec2:CreateTags",
                      "ec2:CreateVpc",
                      "ec2:DeleteInternetGateway",
                      "ec2:DeleteRoute",
                      "ec2:DeleteRouteTable",
                      "ec2:DeleteSecurityGroup",
                      "ec2:DeleteSubnet",
                      "ec2:DeleteTags",
                      "ec2:DeleteVpc",
                      "ec2:DescribeAccountAttributes",
                      "ec2:DescribeAvailabilityZones",
                      "ec2:DescribeInstances",
                      "ec2:DescribeInternetGateways",
                      "ec2:DescribeKeyPairs",
                      "ec2:DescribeNetworkInterface",
                      "ec2:DescribeRouteTables",
                      "ec2:DescribeSecurityGroups",
                      "ec2:DescribeSubnets",
                      "ec2:DescribeTags",
                      "ec2:DescribeVpcAttribute",
                      "ec2:DescribeVpcs",
                      "ec2:DetachInternetGateway",
                      "ec2:DisassociateRouteTable",
                      "ec2:ModifyVpcAttribute",
                      "ec2:RunInstances",
                      "ec2:TerminateInstances",
                      "ecr:*",
                      "ecs:*",
                      "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer",
                      "elasticloadbalancing:AttachLoadBalancerToSubnets",
                      "elasticloadbalancing:ConfigureHealthCheck",
                      "elasticloadbalancing:CreateLoadBalancer",
                      "elasticloadbalancing:DeleteLoadBalancer",
                      "elasticloadbalancing:DeleteLoadBalancerListeners",
                      "elasticloadbalancing:DeleteLoadBalancerPolicy",
                      "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
                      "elasticloadbalancing:DescribeInstanceHealth",
                      "elasticloadbalancing:DescribeLoadBalancerAttributes",
                      "elasticloadbalancing:DescribeLoadBalancerPolicies",
                      "elasticloadbalancing:DescribeLoadBalancerPolicyTypes",
                      "elasticloadbalancing:DescribeLoadBalancers",
                      "elasticloadbalancing:ModifyLoadBalancerAttributes",
                      "elasticloadbalancing:SetLoadBalancerPoliciesOfListener",
                      "iam:AttachRolePolicy",
                      "iam:CreateRole",
                      "iam:GetPolicy",
                      "iam:GetPolicyVersion",
                      "iam:GetRole",
                      "iam:ListAttachedRolePolicies",
                      "iam:ListInstanceProfiles",
                      "iam:ListRoles",
                      "iam:ListGroups",
                      "iam:ListUsers",
                      "iam:CreateInstanceProfile",
                      "iam:AddRoleToInstanceProfile",
                      "iam:ListInstanceProfilesForRole",

                      "iam:ListServerCertificates",
		                  "elasticloadbalancing:DescribeSSLPolicies"
                  ],
                  "Resource": "*"
                }
              ]
            }
            ```

1. **Create role to use with the ECS cluster to create** called `ecsInstanceRole` with this polciy, AmazonEC2ContainerServiceforEC2Role 

1. **Create a group and user allowed to deploy containers** (via updating services, creating tasks, not task definitions). 

    1. Create a group for the needed perimssions called `EcsDeploy`. Create a user and put it in.

    1. Add this policy the group: AmazonEC2ContainerRegistryFullAccess policy (allows ECR registry creation & pushing, but not management of ECS services, tasks, etc)

    1. Create and add a new policy called `EC2ContainerServiceDeploy` to the group with these permissions (deploying ECS only, but not setting up app via service/etc)

        ```json
        {
        "Version": "2012-10-17",
        "Statement": [
              {
                  "Sid": "Stmt1481041359000",
                  "Effect": "Allow",
                  "Action": [
                      "ecr:BatchCheckLayerAvailability",
                      "ecr:BatchGetImage",
                      "ecr:GetDownloadUrlForLayer",
                      "ecr:GetAuthorizationToken",
                      "ecs:DeregisterTaskDefinition",
                      "ecs:DescribeClusters",
                      "ecs:DescribeContainerInstances",
                      "ecs:DescribeServices",
                      "ecs:DescribeTaskDefinition",
                      "ecs:DescribeTasks",
                      "ecs:ListClusters",
                      "ecs:ListContainerInstances",
                      "ecs:ListServices",
                      "ecs:ListTaskDefinitionFamilies",
                      "ecs:ListTaskDefinitions",
                      "ecs:ListTasks",
                      "ecs:RegisterContainerInstance",
                      "ecs:RegisterTaskDefinition",
                      "ecs:RunTask",
                      "ecs:StartTask",
                      "ecs:StopTask",
                      "ecs:UpdateContainerAgent",
                      "ecs:UpdateService"
                  ],
                  "Resource": [
                      "*"
                  ]
              }
          ]
        }
        ```


    1. Create key pair for deployment auth

## *Part 2.* Setting up ECS for application deployment

1. Log in as new IAM account to set up cluster.

1. Create cluster (or use existing and skip to the next step)
    1. Use `ecsContainerRole`
    1. Note VPC, security group created for open ports

1. Create ECR registry named for the app (i.e. my-app).

1. Create AWS certificate in the ACM service to be used with the app's secured URLs via a load balancer.

TODO: - AFTER TASK DEF & SVC (APP START)?
1. Set up load balancer:
    1. Create load balancer.
    1. Use VPC used in sec. group for ECS EC2 instance, and that sec. group for the load balancer. Check that you can hit app via DNS name for created load balancer. 
    1. Set up subdomain for already registered domain name:
        1. Create a hosted zone for the subdomain/etc you want to host using AWS Route 53. 
        1. Add resource record sets for the new subdomain to Route 53 hosted zone. 
        1. Update the DNS service for the parent domain by adding name server records for the subdomain. 

    1. Add endpoints for each task definition (app instance / environment)
        - Development: port https/44443 to container port 8080; http/8080 to 8080 (health check)
        - Staging: port https/44444 to container on port 8082; 8082 to 8082 (health check)
        - Production: https/443 to container on port 80; 80 to 80 (health check)
    1. Select 2 availability zones
    1. ***!*** Use certificate created above to create URLs for each   & use latest predefined policy
        1. Update domain name registrar with name service records for subdomain created in AWS.
        1. TODO: Set up load balancer to point to dev/stg/prod 
    1. Make sure security group allows desired incoming ports
    1. Set up health check to hit open endpoint

1. Prepare a task definition file for your app, including each container you have for the app. Then duplicate & update the task definition for each environment. You should end up with 1 task definition for each environment, with each task definition declaring all the containers it needs for the app, each pointing to the ECR app image, and each containing the appropriate settings for its environment (ports to expose, etc).
    - A sample task definition for an API app that uses an app contianer & database container is available in a json file in this source code. You can update it and use it. 
    - You can generate a task definition file from a Docker compose file with the ecs-cli, like this `ecs-cli compose -f *<docker compose file>* create`.

1. Create the task deinitions in ECS, by going into the ECS UI, going to Task Definitions and creating one. You can paste in the task definition json.

1. Create a service for each instance of the app (dev/stg/prod): go to ECS > Clusters > desired cluster and creating one. Choosing the task definition, and set the minumum healthy count to 0 (so all containers can be stopped before starting an updated one). Repeat for each environment. This should start your app instances.

## *Part 3.* Setting up CI for deployment

1. Link your GitHub repo to the cloud-based CI of your choice. 

1. Set up these environment variables in the CI tool with the appropriate values:

    AWS_ACCESS_KEY
    AWS_SECRET_ACCESS_KEY
    AWS_ACCOUNT_ID
    AWS_DEFAULT_REGION
    CLUSTER_NAME (ECS cluster name)
    *Per environment*
    SERVICE (the name of the ECS service linked to the task definition for your app)
    IMAGE_NAME (base name of your docker iamge from your docker/compose file, i.e. my-app-dev)

1. View the `.travis.yml` in this repo to see how the CI tool is set up. The image tagging, image repo push & deploy are triggered in this CI configuration file by calling a bash script. The script deploys based on branch.

If you aren't using TravisCI, you must create a new configuration file for your respective CI tool (to replace .travis.yml), but only minor tweaks will be necessary for the required syntax, since the bash scripts do the heavy lifting and can be reused.

1. Deployment based on branch

    - master *deploys to* my-app-dev, staging *deploys to* staging, production *deploys to* prod

1. Put the CI configuration file (.travis.yml in this sample) it into the root of your repo, configure the CI tool with the push/PR build options you want, ensure the environment variables above are in, and check in to your repo to trigger a build.