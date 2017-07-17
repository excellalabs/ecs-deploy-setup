# My App

| Branch        | Environment   | Image, Container, Task Definition & Service names  | URL |
| ------------- | :-----------: | :------------------------------------------------: | :-------------: |
| develop    | Local   | none | n/a |
| master     | Demo    | my-app-demo | [https://myapp.com:44300](https://myapp.com:44300) |
| staging    | Staging | my-app-prod | [https://myapp.com:44301](https://myapp.com:44301) |
| production | Product | my-app-prod | [https://myapp.com](https://myapp.com) |

This Dockerized API-based application is ready to deploy to AWS ECS. The core AWS infrastructure creation is automated via a CloudFormation template (see instructions below). The application uses the following key infrastructure:

- **AWS EC2 Container Service (ECS)** (currently with two EC2 instances to allow enough memory for blue/green deployment)
- AWS supporting infrastructure including EC2 **Application Load Balancer**
- **Route53** for the subdomain and the AWS Certificate (myapp.com - that subdomain is delegated to AWS Route53)
- Deployment IAM account, S3 backup IAM account (read/write to bucket), ECS admin IAM account
- **CloudWatch** for centralized logging of the container log output
- **TravisCI**

The application stack is as followed:

- ASP.NET Core 1.1 for the API
- PostgreSQL 9.6.3 in a container with the data file mounted to the host ECS instance
- cron in a container that runs backups against the database, and saves them to S3

**The key resources are:**

- [CloudFormation script](/deploy-ecs/infra-ecs-my-app.json) that will set up the core needed infrastructure and initally deploy the app; also a good starting place for new AWS-based applications & to get a prototype up fast.
- IAM accounts (deployment, backup) in Secret Server prefixed with the name `My App`
- ECS Cluster - `aurora`
- Containers apart of the app: API (ASP.NET Core), database (Postgres), database backup cron job container (production only)
  - Database hosts and credentials and in Secret server prefixed with the name `My App`
- Nameing convention based on environment: `my-app-` + `dev` for local, `demo`, `stg` and `prod`
  - This is used for **images, containers, services and task definitions**, and allows the deployment pipeline to easily deploy based on branch
- S3 bucket for database backups: `my-app-db-backups`
- Utility scripts in src/scripts for to ease things like creating migrations, manual db backups, db restores, db drop schema, etc.
- CloudWatch logs under `my-app-logs`
- ECS logs on the EC2 instances in `/var/lib/docker/containers/<ContainerID>/<ContainerID>-json.log` (shows ECS events like updating a service)

# Setting up locally

## Installing the self-signed certificate for development

1. Pull the latest and rebuild the My App containers: docker-compose up --build
1. Go to Chrome’s settings > Show advanced settings… > Manage Certificates
1. Import the cert: src/app.pfx (password: testPassword)
1. Install it on the Local Machine, and choose Windows Trusted Root Certification Authority (may have to restart Chrome)

## Run the application (in a container)

- This will build (if needed) the image, and create & run a container in the background from it, setting app the proper parameters including exposing the API port. The database will be created automatically.
- The application will start up on the port set in the Dockerfile's ASPNETCORE_URLS environment variable, and mapped to the host port set in the docker-compose file.

1. To start the containers, run:

        `docker-compose up` (you can add `-d` to run them in the background, and use `docker logs <container name>` etc., as needed)

    You can test the API database connection by posting this (note, this endpoint may be removed in future versions):

        `curl -H "Content-Type: application/json" -X POST -d '{"lastname":"Posted"}' https://localhost/api/v1.0/applicant`

## Developing

1. Dotnet Watch will be running. When you save code changes, it will rebuild and rerun the applicant. Watch the progress in the console output.
1. Run the src/go-tests.sh script to run the tests (while app is running)
1. If you need to rebuild the image, for example if you've changed the Docker files, you can run `docker-compose up -d --build`.
1. To stop your containers, run `docker-compose stop` (or ctrl-C if running in interactive mode). You can run `docker-compose down` to stop and remove them (and other Docker resources created as part of your Compose file), if needed.

### Adding database migrations in the container

1. Run the following script (from src/) passing the name of the migration you'd like: `./scripts/migration.sh <MIGRATION_NAME>` 

#### OR: Manually logging into the container and running the dotnet command 

1. Log into the app container with this command:

    `docker exec -it <container name> bash`

1. Add the migration:

    `dotnet ef migrations add <migration name>`

1. The database will update when you run the app.

- NOTE: You can drop the database by running this:

    `dotnet ef database drop`

### Manage the database via psql CLI (pgAdmin can be used as a GUI tool)

1. Log into the postgres container (see instructions above)

1. Run `psql -h localhost -p 5432 -d skillustrator -U postgres --password`. Enter `password`.

1. To list tables in the database type, `\dt`. You can do other database operations here. 

1. To exit type, `\q`

# Deployment and Maintenance

TravisCI handles deploying based on code changes that are merged into the branches listed below. Currently, in order to have images that were successfully deployed onto Demo promoted to staging/production, a new image only gets built when merging to master (which Demo uses). When merging to Staging or Production, that image same image is used.

Deployments are done by TravisCI running bash scripts in the /deploy-ecs/travisCI folder, whicih use Docker to build, and aws-cli to push images to ECR & to deploy them to ECS (by creating a new task defition revision, and updating the service with it.

- `develop` is the active development branch. Travis will currently build & test any updated PR.
- Merge to `master` to have TravisCI build, test & deploy to the demo environment
- Merge to `master` -> `staging` to deploy to the staging environment
- Merge to `staging` -> `production` to deploy to production
- the .travis.yml calls upon bash scripts in the /deploy folder for pushing & deploying images and containers to ECS
- There are Docker Compose files (for environment variables, named volumes, etc), ECS Task Definitions and Services for each environment named respectively: my-app-demo, my-app-stg, my-app-prod

### Hotfixes

You can set the TravisCI HOTFIX environment variable to true to override images only being built on Demo to promote, as this will rebuild and deploy when merged to any of the main branches.

For example, set it to true, then create a hotfix branch, and merge that directly into staging/production and a new image will be build and deployed in both cases.

![Deployment pipeline](CI-pipeline.png)

#### IMPORTANT NOTE: Changing Task Definitions

To change settings and environment variblaes for the deployed app (in its respective environment), you must change the respective task definiton. You can change them in the AWS ECS console, or via the CLI. After changing them, you must deploy manually (update the respective service with the new task definition in the AWS ECS console). Otherwise, TravisCI will use the task definition for the latest deployed version of the app, ignoring your new version thus new settings.

## Database backups

- A container runs along with the app that is responsible for backing up on a schedule, using a cron job & bash scripts, and storing the backup in S3.
- There are scripts for running it manually in the scripts folder.
- There is a directory in the repo called dbbackup which has the Dockerfile and scripts for the job to create the image, which the docker-compose-prod.yml file uses.
- It uses an AWS access key that only has permissions to read/write to the S3 bucket where the backups go.

**Backup Process**

1. The database backup container spins up with Compose (and ECS task definition) and starts a cron job, that runs the backup job once a day.
1. The S3 bucket and other configuration is set in the docker-compose-prod.yml (the backup job container only runs in production) and ECS task definition files (s3://my-app-db-backups)
1. The S3 bucket will keep the last 15 days of backup (pruning using the bucket's object lifecycle management).

## Maintenance

Periodically:

- Monitor database backups are getting put in the S3 bucket: `my-app-db-backups`. If not, check the `my-app-prod-dbbackup` container where the production app is deployed to ensure it's running its cron job.
- Monitor CloudWatch logs under `my-app-logs`
- Monitor ECS logs on the EC2 instances in `/var/lib/docker/containers/<ContainerID>/<ContainerID>-json.log` (shows ECS events like updating a service). **Ensure they are not getting too large.**

# Setting up AWS & CI Infrastructure

AWS with ECS (EC2 Container Service) is used to host this application. There is a CloudFormation template available [here](/deploy-ecs/infra-ecs-my-app.json), which documents the architecture and automates the creation of all the needed infrastructure, using the specified images below.

There is [**detailed information and manual installation instructions here**](./README-CI-and-ECS-setup.md).

**Resource Reference List:**

- ECS Cluster (w/2 EC2 instances)
- EC2 Application Load Balancer
- An IAM account for deployment, and one management/setting up ECS (see both in Secret Server searching "ecs"). They are in groups with the needed policies.
- CloudFront for central logging of the containers
- Route53 for the subdomain and the AWS Certificate
- CloudFormation for the infrastructure template
- TravisCI

![ECS architecture](ECS-infra-my-app-basic.png)

### Setting up the ECS & surrounding infrastructure

1. Initially create ECR repositories called my-app (API app) and my-app-dbbackup (db backup cron job image).
1. Build & push the 2 images to the respective repositories (note, you can use TravisCI or the scripts it uses to do this initially. After the inital deploy, TravisCI will do all future deployments).
    <INSERT HERE>
1. Set up the S3 bucket for the database backup job, per the instructions below.
1. Run this [CloudFormation template](/deploy-ecs/infra-ecs-my-app.json). You will need access to all the resources it references, or be a full admin. This creates the complete foundational infrastructure with 1 instance in the cluster, and runs the app's containers. This will get the app up and running with everything else needed, including IAM accounts and CloudWatch logs for each container (API, database, database backup job). You can then set up a domain name with Route53, increase container instances for scaling or blue/green deployment (requires 2), etc.
1. Set up TravisCI per the instructions below.
1. NOTE: for manual AWS infrastructure setup details with more explanation of the settings, see [README-CI-and-ECS-setup.md](./README-CI-and-ECS-setup.md).

### Setting up CI for deployment

1. Link your GitHub repo to the cloud-based CI of your choice.

1. Set up these environment variables in the CI tool with the appropriate values:

    AWS_ACCESS_KEY
    AWS_SECRET_ACCESS_KEY
    AWS_ACCOUNT_ID
    AWS_DEFAULT_REGION
    CLUSTER_NAME (ECS cluster name)
    *Per environment*
    SERVICE_BASENAME (the name of the ECS service linked to the task definition for your app)
    IMAGE_BASENAME (base name of your docker iamge from your docker/compose file, i.e. my-app-dev)
    POSTGRES_PASSWORD_PROD/etc - will set that password for the database if not created, and use it in the app
    HOTFIX (true to override images only being built on Demo to promote, as this will rebuild and deploy when merged to any of the main branches)

1. View the `.travis.yml` in this repo to see how the CI tool is set up. The image tagging, image repo push & deploy are triggered in this CI configuration file by calling  bash scripts. Deploys are based on branch.

If you aren't using TravisCI, you must create a new configuration file for your respective CI tool (to replace `.travis.yml`), but only minor tweaks will be necessary for the required syntax, since the bash scripts do the heavy lifting and can be reused.

### Deployment based on branch

TravisCI handles deploying based on code changes that are merged into the branches listed below. Currently, in order to have images that were successfully deployed onto Demo promoted to staging/production, a new image only gets built when merging to master (which Demo uses). When merging to Staging or Production, that image same image is used. The deployment bash scripts would need to be slightly tweaked for a hotfix situation.

- `develop` is the active development branch. Travis will currently build & test any updated PR.
- Merge to `master` to have TravisCI build, test & deploy to the demo environment (https://myapp.com:44300)
- Merge to `master` -> `staging` to deploy to the staging environment (https://myapp.com:44301)
- Merge to `staging` -> `production` to deploy to production (https://myapp.com)
- the .travis.yml calls upon bash scripts in the /deploy folder for pushing & deploying images and containers to ECS

### Set up S3 for backup job

The backup job uses:

- S3 Bucket w/account with only read/write access to that (ECS_Admin account also has access)
- Cron job in container (defined in docker-compose-prod.yml)

You must set up the bucket for the backup job (embedded in the production version of the app) to use. Setup steps:

1. Create a bucket for the backups to be saved in by going to S3 and creating a bucket called `s3-my-app-db-backups`
1. Create a new policy for read/write access to this bucket and add it to the ecsAdmins group:

    ```
    {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::my-app-db-backups"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3::: my-app-db-backups/*"
            ]
        }]
    }
    ```

1. Create a new user for this bucket access, when saving database backups, called “my-app-dbbackup” and apply this policy to the user.
1. Apply the policy to the ECS_Admin account too so it can retrieve the backups as needed.
1. Set up a job to delete backups older than a certain number of days (up to you - i.e. delete backups older than 7 days).

# Additional Resources

- [ECS with a CI pipeline Overview slide deck](AWS-ECS-with-a-CI-pipeline-Overview.pptx)
    
    *Includes ECS key docs on last slide:*

        - Overview & Key Concepts
        - Reference architecture for ECS w/deployment pipeline (CloudFormation)
        - ECS IAM Policies
        - Core Setup Steps