#!/bin/bash
set -e

source /init.sh

printmainstep "Déclenchement du déploiement du macroservice"
printstep "Vérification des paramètres d'entrée"

init_env
int_gitlab_api_env

PROJECT_PREFIX=${PROJECT_NAME%-*}
PROJECT_DEPLOY_NAME="$PROJECT_PREFIX-deploy"

echo "PROJECT_NAME        : $PROJECT_NAME"
echo "PROJECT_NAMESPACE   : $PROJECT_NAMESPACE"
echo "PROJECT_DEPLOY_NAME : $PROJECT_DEPLOY_NAME"

PROJECT_DEPLOY_ID=`curl --silent --noproxy '*' --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects?search=$PROJECT_DEPLOY_NAME" | jq --arg project_namespace "$PROJECT_NAMESPACE" '.[] | select(.namespace.name == "\($project_namespace)")' | jq .id`

if [[ $PROJECT_DEPLOY_ID != "" ]]; then

    printstep "Préparation du déclencheur trigger_deploy sur le projet $PROJECT_DEPLOY_NAME"
    PIPELINE_TOKEN=`curl --silent --noproxy '*' --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/triggers" | jq '.[] | select(.description == "trigger_deploy")' | jq .token | tr -d '"'`

    if [[ -z $PIPELINE_TOKEN ]]; then
        printinfo "Création du déclencheur manquant trigger_deploy"
        PIPELINE_TOKEN=`curl --silent --noproxy '*' --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" --form description="trigger_deploy" "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/triggers" | jq .token | tr -d '"'`
    fi

    printstep "Déclenchement du déploiement sur le projet $PROJECT_DEPLOY_NAME"
    PIPELINE_ID=`curl --silent --noproxy '*' --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -XPOST "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/trigger/pipeline" -d "token=$PIPELINE_TOKEN" -d "ref=$BRANCH_NAME" | jq .id `
    sleep 5
    
    DEPLOY_JOB_ID=`curl --silent --noproxy '*' --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/pipelines/$PIPELINE_ID/jobs/" | jq '.[] | select(.name | startswith("deploy")) | .id'`
    
    if [[ $DEPLOY_JOB_ID != "" ]]; then
        
        while :
        do
            JOB_STATUS=`curl --silent --noproxy '*' --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/jobs/472" | jq .status | tr -d '"'`
            if [[ $JOB_STATUS == "failed" ]] || [[ $JOB_STATUS == "success" ]]; then break; fi
            sleep 5
        done
        
        printstep "Affichage des logs distants du job deploy du projet $PROJECT_DEPLOY_NAME"
        printinfo "Lien d'accès d'orifine des logs distants : $GITLAB_API_URL/$PROJECT_NAMESPACE/$PROJECT_DEPLOY_NAME/builds/$DEPLOY_JOB_ID"
        curl --silent --noproxy '*' --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/jobs/$DEPLOY_JOB_ID/trace"
        if [[ $JOB_STATUS == "failed" ]]; then exit 1; fi
        if [[ $JOB_STATUS == "success" ]]; then exit 0; fi

    else
        printerror "Aucun job dont le nom commence par deploy disponible dans le projet $PROJECT_DEPLOY_NAME"
        exit 1
    fi
else
    printerror "Pas de déclenchement de déploiement possible, le projet $PROJECT_DEPLOY_NAME n'existe pas pour ce macroservice"
    exit 1
fi