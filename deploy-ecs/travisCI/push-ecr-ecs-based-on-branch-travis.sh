#! /bin/bash

############ Env vars needed in Travis ############################################################
#   Pass in/profile:
# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY

AWS_DEFAULT_REGION="us-east-1"
AWS_ACCOUNT_ID=090999229429

CLUSTER_NAME="staging-tests"
SERVICE_BASENAME="skillustrator"
#   (i.e. my-app; -dev will get appended for the dev environment, making my-app-dev)
IMAGE_BASENAME="skillustrator"
#   (i.e. my-app; -dev will get appended for the dev environment, making my-app-dev)

## Env vars generated by Travis
TRAVIS_BRANCH="master"
TRAVIS_COMMIT="123450"
################################################################################################

pushToEcr () {
    eval $(aws ecr get-login --region $AWS_DEFAULT_REGION)
        
    echo "Pushing $1 to $2"
    docker tag $1 $2:latest
    docker push $2:latest
    docker tag $1 $2:$TRAVIS_COMMIT 
    docker push $2:$TRAVIS_COMMIT 
    echo "Pushed $2"

    # for tag in {$TRAVIS_COMMIT,latest}; do  
    #   docker tag $2 $2:${tag}      
    #   docker push $2:${tag}      
    # done 
}

if [ -z "$TRAVIS_PULL_REQUEST" ] || [ "$TRAVIS_PULL_REQUEST" == "false" ]; then
    
    ENV_SUFFIX="dev"
    if [ "$TRAVIS_BRANCH" == "master" ]; then 
      ENV_SUFFIX="-demo"
    elif [ "$TRAVIS_BRANCH" == "staging" ]; then 
      ENV_SUFFIX="-stg"
    elif [ "$TRAVIS_BRANCH" == "production" ]; then 
      ENV_SUFFIX="-prod"
    else 
      return 0;  
    fi

    IMAGE_FULLNAME=$IMAGE_BASENAME$ENV_SUFFIX
    IMAGE_URL_BASE=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_BASENAME
    IMAGE_URL=$IMAGE_URL_BASE:$TRAVIS_COMMIT
    SERVICE_FULLNAME=$SERVICE_BASENAME$ENV_SUFFIX

    pushToEcr $IMAGE_FULLNAME $IMAGE_URL_BASE
    
    echo "Deploying $TRAVIS_BRANCH on service $SERVICE_FULLNAME (cluster: $CLUSTER_NAME)"
    deploy-ecs/ecs-deploy.sh -c $CLUSTER_NAME -n $SERVICE_FULLNAME -i $IMAGE_URL -r $AWS_DEFAULT_REGION
fi 
