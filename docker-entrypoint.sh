#!/bin/bash
set -e

source /init.sh

printmainstep "Déclenchement du déploiement du macroservice"
printstep "Vérification des paramètres d'entrée"

init_env
int_gitlab_api_env

PROJECT_DEPLOY_NAME="$PROJECT_NAMESPACE-deploy"

echo "PROJECT_NAME        : $PROJECT_NAME"
echo "PROJECT_NAMESPACE   : $PROJECT_NAMESPACE"
echo "PROJECT_DEPLOY_NAME : $PROJECT_DEPLOY_NAME"

PROJECT_DEPLOY_ID=`curl --silent --noproxy '*' --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects?search=$PROJECT_DEPLOY_NAME" | jq .[0].id`

if [[ $PROJECT_DEPLOY_ID != "null" ]]; then

    printstep "Préparation du déclencheur trigger_deploy sur le projet $PROJECT_DEPLOY_NAME"
    PIPELINE_TOKEN=`curl --silent --noproxy '*' --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/triggers" | jq '.[] | select(.description == "trigger_deploy")' | jq .token | tr -d '"'`

    if [[ -z $PIPELINE_TOKEN ]]; then
        printinfo "Création du déclencheur manquant trigger_deploy"
        PIPELINE_TOKEN=`curl --silent --noproxy '*' --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" --form description="trigger_deploy" "$GITLAB_API_URL/projects/13/triggers" | jq .token | tr -d '"'`
    fi

    printstep "Déclenchement du déploiement sur le projet $PROJECT_DEPLOY_NAME"
    PIPELINE_ID=`curl --silent --noproxy '*' -XPOST "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/trigger/pipeline" -d "token=$PIPELINE_TOKEN" -d "ref=master" | jq .id `
    sleep 5
    
    curl --silent --noproxy '*' --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/pipelines/$PIPELINE_ID/jobs/" | jq '.[] | select(.name == "deploy_dev")'

else
    printerror "Pas de déclenchement de déploiement possible, le projet $PROJECT_DEPLOY_NAME n'existe pas pour ce macroservice"
    exit 1
fi