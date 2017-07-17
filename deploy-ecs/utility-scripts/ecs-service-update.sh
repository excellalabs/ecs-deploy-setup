CLUSTER_NAME=aurora
SERVICE_NAME=my-app-dev
TASK_DEFINITION=my-app-dev

aws ecs update-service --cluster $CLUSTER_NAME --service $SERVICE_NAME --task-definition $TASK_DEFINITION