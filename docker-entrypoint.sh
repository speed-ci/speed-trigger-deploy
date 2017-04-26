#!/bin/bash
set -e

printstep() {
    # 36 is blue
    echo -e "\033[36m\n== ${1} \033[37m \n"
}
printmainstep() {
   # 35 is purple
   echo -e "\033[35m\n== ${1} \033[37m \n"
}
printinfo () {
    # 32 is green
    echo -e "\033[32m==== INFO : ${1} \033[37m"
}
printwarn () {
    # 33 is yellow
    echo -e "\033[33m==== ATTENTION : ${1} \033[37m"
}
printerror () {
    # 31 is red
    echo -e "\033[31m==== ERREUR : ${1} \033[37m"
}

init_env () {
    CONF_DIR=/conf/
    if [ ! -d $CONF_DIR ]; then
        printerror "Impossible de trouver le dossier de configuration $CONF_DIR sur le runner"
        exit 1
    else
        source $CONF_DIR/variables
    fi
    APP_DIR=/usr/src/app/
    if [ ! -d $APP_DIR ]; then
        printerror "Impossible de trouver le dossier du code source de l'application $APP_DIR sur le runner"
        exit 1
    fi    
    if [[ -z $GITLAB_TOKEN ]]; then
        printerror "La variable GITLAB_TOKEN n'est pas présente, sortie..."
        exit 1
    fi
}

printmainstep "Déclenchement du déploiement du macroservice"
printstep "Vérification des paramètres d'entrée"

init_env

REPO_URL=$(git config --get remote.origin.url | sed 's/\.git//g' | sed 's/\/\/.*:.*@/\/\//g')
GITLAB_URL=`echo $REPO_URL | grep -o 'https\?://[^/]\+/'`
GITLAB_API_URL="$GITLAB_URL/api/v4"
PROJECT_NAME=${REPO_URL##*/}
PROJECT_NAMESPACE=${PROJECT_NAME%-*}
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
    curl --silent --noproxy '*' -XPOST "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/trigger/pipeline" -d "token=$PIPELINE_TOKEN" -d "ref=master"
else
    printerror "Pas de déclenchement de déploiement possible, le projet $PROJECT_DEPLOY_NAME n'existe pas pour ce macroservice"
    exit 1
fi