#!/bin/bash
set -e

source /init.sh

printmainstep "Déclenchement du déploiement du macroservice"
printstep "Vérification des paramètres d'entrée"

init_env
int_gitlab_api_env

PROJECT_DEPLOY_NAME="$PROJECT_NAMESPACE-deploy"

printinfo  "PROJECT_NAME        : $PROJECT_NAME"
printinfo  "PROJECT_NAMESPACE   : $PROJECT_NAMESPACE"
printinfo  "PROJECT_DEPLOY_NAME : $PROJECT_DEPLOY_NAME"

PROJECT_DEPLOY_ID=`myCurl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects?search=$PROJECT_DEPLOY_NAME" | jq --arg project_namespace "$PROJECT_NAMESPACE" '.[] | select(.namespace.name == "\($project_namespace)") | .id'`

if [[ $PROJECT_DEPLOY_ID != "" ]]; then

    printstep "Préparation du projet $PROJECT_NAMESPACE/$PROJECT_DEPLOY_NAME"
    GITLAB_CI_USER_MEMBERSHIP=`myCurl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/members?query=$GITLAB_CI_USER" | jq .[0]`
    if [[ $GITLAB_CI_USER_MEMBERSHIP == "null" ]]; then 
        printinfo "Ajout du user $GITLAB_CI_USER manquant au projet $PROJECT_NAMESPACE/$PROJECT_DEPLOY_NAME"
        myCurl --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/members" -d "user_id=$GITLAB_CI_USER_ID" -d "access_level=40"
    fi
    
    printstep "Préparation du déclencheur trigger_deploy sur le projet $PROJECT_NAMESPACE/$PROJECT_DEPLOY_NAME"
    PIPELINE_TOKEN=`myCurl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" --header "SUDO: $GITLAB_USER_ID" "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/triggers" | jq -r --arg gitlab_user_id "$GITLAB_USER_ID" '.[] | select(.description == "trigger_deploy" and (.owner.id | tostring == "\($gitlab_user_id)")) | .token'`

    if [[ -z $PIPELINE_TOKEN ]]; then
        printinfo "Création du déclencheur manquant trigger_deploy"
        PIPELINE_TOKEN=`myCurl --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" --header "SUDO: $GITLAB_USER_ID" --form description="trigger_deploy" "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/triggers" | jq -r .token`
    fi

    printstep "Déclenchement du déploiement sur le projet $PROJECT_NAMESPACE/$PROJECT_DEPLOY_NAME"
    if [[ $BRANCH_NAME == master ]]; then
        DEPLOY_BRANCH_NAME=dev
    else
        DEPLOY_BRANCH_NAME=$BRANCH_NAME
    fi
    PIPELINE_ID=`myCurl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -XPOST "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/trigger/pipeline" -d "token=$PIPELINE_TOKEN" -d "ref=$DEPLOY_BRANCH_NAME" -d "variables[SERVICE_TO_UPDATE]=$PROJECT_NAME" -d "variables[TRIGGER_USER_ID]=$GITLAB_USER_ID" | jq .id`
    sleep 5
    
    DEPLOY_JOB_ID=`myCurl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/pipelines/$PIPELINE_ID/jobs/" | jq '.[] | select(.name | startswith("deploy")) | .id'`
    
    if [[ $DEPLOY_JOB_ID != "" ]]; then
        
        while :
        do
            JOB_STATUS=`myCurl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/jobs/$DEPLOY_JOB_ID" | jq -r .status`
            if [[ $JOB_STATUS != "pending" ]] && [[ $JOB_STATUS != "running" ]]; then break; fi
            sleep 5
        done

        printinfo "Status final du job deploy du projet $PROJECT_NAMESPACE/$PROJECT_DEPLOY_NAME : $JOB_STATUS"

        printstep "Affichage des logs distants du job deploy du projet $PROJECT_NAMESPACE/$PROJECT_DEPLOY_NAME"
        printinfo "Lien d'accès aux logs distants d'origine : $GITLAB_URL/$PROJECT_NAMESPACE/$PROJECT_DEPLOY_NAME/builds/$DEPLOY_JOB_ID"
        sleep 5
        echo ""
        curl --silent --noproxy '*' --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/jobs/$DEPLOY_JOB_ID/trace"
        if [[ $JOB_STATUS != "success" ]]; then exit 1; fi

    else
        printerror "Aucun job dont le nom commence par deploy disponible dans le projet $PROJECT_NAMESPACE/$PROJECT_DEPLOY_NAME"
        exit 1
    fi
else
    printerror "Pas de déclenchement de déploiement possible, le projet $PROJECT_NAMESPACE/$PROJECT_DEPLOY_NAME n'existe pas pour ce macroservice"
    exit 1
fi