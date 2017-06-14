CLUSTER_NAME=aurora
SERVICE_NAME=defic-svc-dev
TASK_DEFINITION=defic-svc-dev

aws ecs update-service --cluster $CLUSTER_NAME --service $SERVICE_NAME --task-definition $TASK_DEFINITION