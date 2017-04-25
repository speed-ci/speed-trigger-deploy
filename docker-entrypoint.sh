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
    if [[ -z $GITLAB_TOKEN ]];then
        printerror "La variable GITLAB_TOKEN n'est pas présente, sortie..."
        exit 1
    fi
}

printmainstep "Déclenchement du déploiement du macro-service"
printstep "Vérification des paramètres d'entrée"

init_env
env

REPO_URL=$(git config --get remote.origin.url | sed 's/\.git//g' | sed 's/\/\/.*:.*@/\/\//g')
GITLAB_URL=`echo $REPO_URL | grep -o 'https\?://[^/]\+/'`
GITLAB_API_URL="$GITLAB_URL/api/v4"
PROJECT_NAME=${REPO_URL##*/}
PROJECT_NAMESPACE=${PROJECT_NAME%-*}

PROJECT_DEPLOY_NAME="$PROJECT_NAMESPACE-deploy"
PROJECT_DEPLOY_ID=`curl --silent --noproxy '*' --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects?search=$PROJECT_DEPLOY_NAME" | jq .[0].id`

if [[ -n $PROJECT_DEPLOY_ID ]];then
    printstep "Déclenchement du déploiement sur le projet $PROJECT_DEPLOY_NAME"
    curl --silent --noproxy '*' --request POST "$GITLAB_API_URL/projects/$PROJECT_DEPLOY_ID/trigger/pipeline?token=75a84c9680233ac890eef9e972b766&ref=master" | jq
fi