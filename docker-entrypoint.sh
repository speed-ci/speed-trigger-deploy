#!/bin/bash
set -e

source /init.sh

printmainstep "Déclenchement du déploiement du macroservice"
printstep "Vérification des paramètres d'entrée"

init_env
int_gitlab_api_env

PROJECT_PREFIX=${PROJECT_NAME%-*}
PROJECT_DEPLOY_NAME="$PROJECT_PREFIX-deploy"
GITLAB_CI_USER="gitlab-ci-sln"

printinfo  "PROJECT_NAME        : $PROJECT_NAME"
printinfo  "PROJECT_NAMESPACE   : $PROJECT_NAMESPACE"
printinfo  "PROJECT_DEPLOY_NAME : $PROJECT_DEPLOY_NAME"

PROJECT_DEPLOY_ID=`curl --silent --noproxy '*' --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects?search=$PROJECT_DEPLOY_NAME" | jq --arg project_namespace "$PROJECT_NAMESPACE" '.[] | select(.namespace.name == "\($project_namespace)")' | jq .id`

if [[ $PROJECT_DEPLOY_ID != "" ]]; then

    printstep "Préparation du projet $PROJECT_NAMESPACE/$PROJECT_DEPLOY_NAME"
    GITLAB_CI_USER_ID=`curl --silent --noproxy '*' --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/users?username=$GITLAB_CI_USER" | jq .[0].id`
    GITLAB_CI_USER_MEMBERSHIP=`curl --silent --noproxy '*' --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/members?query=$GITLAB_CI_USER" | jq .[0]`
    if [[ $GITLAB_CI_USER_MEMBERSHIP == "null" ]]; then 
        printinfo "Ajout du user $GITLAB_CI_USER manquant au projet $PROJECT_NAMESPACE/$PROJECT_DEPLOY_NAME"
        curl --silent --noproxy '*' --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/members" -d "user_id=$GITLAB_CI_USER_ID" -d "access_level=40"
    fi
    
	IMPERSONATION_TOKEN=`curl --silent --noproxy '*' --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/users/$GITLAB_USER_ID/impersonation_tokens" | jq '.[] | select(.name == "trigger_jobs" and .active) | .token' | tr -d '"'`

    if [[ -z $IMPERSONATION_TOKEN ]]; then
        printinfo "Création de l'impersonationtoken manquant trigger_jobs pour le user courant"
		IMPERSONATION_TOKEN=`curl --silent --noproxy '*' --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/users/$GITLAB_USER_ID/impersonation_tokens" -d "name=trigger_jobs" -d "scopes[]=api" | jq .token | tr -d '"'`
	fi    
    
    printstep "Préparation du déclencheur trigger_deploy sur le projet $PROJECT_NAMESPACE/$PROJECT_DEPLOY_NAME"
    PIPELINE_TOKEN=`curl --silent --noproxy '*' --header "PRIVATE-TOKEN: $IMPERSONATION_TOKEN" "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/triggers" | jq --arg gitlab_user_id "$GITLAB_USER_ID" '.[] | select(.description == "trigger_deploy" and .owner.id == $gitlab_user_id)' | jq .token | tr -d '"'`
    
    if [[ -z $PIPELINE_TOKEN ]]; then
        printinfo "Création du déclencheur manquant trigger_deploy pour le user courant"
        PIPELINE_TOKEN=`curl --silent --noproxy '*' --request POST --header "PRIVATE-TOKEN: $IMPERSONATION_TOKEN" --form description="trigger_deploy" "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/triggers" | jq .token | tr -d '"'`
    fi

    printstep "Déclenchement du déploiement sur le projet $PROJECT_NAMESPACE/$PROJECT_DEPLOY_NAME"
    PIPELINE_ID=`curl --silent --noproxy '*' --header "PRIVATE-TOKEN: $IMPERSONATION_TOKEN" -XPOST "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/trigger/pipeline" -d "token=$PIPELINE_TOKEN" -d "ref=$BRANCH_NAME" -d "variables[SERVICE_TO_UPDATE]=$PROJECT_NAME" | jq .id `
    sleep 5
    
    DEPLOY_JOB_ID=`curl --silent --noproxy '*' --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/pipelines/$PIPELINE_ID/jobs/" | jq '.[] | select(.name | startswith("deploy")) | .id'`
    
    if [[ $DEPLOY_JOB_ID != "" ]]; then
        
        while :
        do
            JOB_STATUS=`curl --silent --noproxy '*' --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/jobs/$DEPLOY_JOB_ID" | jq .status | tr -d '"'`
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