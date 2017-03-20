ENV_SUFFIX="-demo"
if [ "$TRAVIS_BRANCH" == "master" ]; then 
  ENV_SUFFIX="-demo"
elif [ "$TRAVIS_BRANCH" == "staging" ]; then 
  ENV_SUFFIX="-stg"
elif [ "$TRAVIS_BRANCH" == "production" ]; then 
  ENV_SUFFIX="-prod"
fi

docker-compose -f src/docker-compose$ENV_SUFFIX.yml build
docker-compose -f src/docker-compose$ENV_SUFFIX.yml up -d && docker ps
