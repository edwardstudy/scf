#!/bin/bash

set -o errexit
set -o xtrace

# where do i live ?
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# configuration
APP=${DIR}/../test-resources/node-env

# login
cf api --skip-ssl-validation ${CF_API}
cf auth ${CF_USERNAME} ${CF_PASSWORD}

# create organization
cf create-org ${ORG}
cf target -o  ${ORG}

# create space
cf create-space ${SPACE}
cf target -s    ${SPACE}

# push an app
(   cd ${APP}
    cf push node-env
)

# delete the app
cf delete -f node-env

# delete space
cf delete-space -f ${SPACE}

# delete org
cf delete-org -f ${ORG}

