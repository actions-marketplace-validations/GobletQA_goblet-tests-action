#!/bin/bash

# 
# Init script to setup the test environment, then execute the tests based on passed in arguments
# Is expected to be run inside a docker container
# Run Tests Examples:
# * From Repos Root Directory on the Host Machine
#   * `yarn dr` => Runs all tests
#   * `GOBLET_BROWSERS=chrome yarn dr select-strategy.feature` => Runs select-strategy feature on chrome
# * When attached to the running containers shell
#   * `/goblet-action/entrypoint.sh`
#   * `GOBLET_BROWSERS=chrome /goblet-action/entrypoint.sh select-strategy.feature`
# 

# Exit when any command fails
set -e
set -o pipefail
source /goblet-action/scripts/logger.sh

export DEBUG=pw:api
# Force headless mode in CI environment
export GOBLET_HEADLESS=true
# Ensure devtools is not turned on
unset $GOBLET_DEV_TOOLS
export GOBLET_MOUNT_ROOT=/home/runner/work
export GH_WORKSPACE_PARENT_DIR=/home/runner/work
export GOBLET_ACT_REPO_LOCATION=/goblet-action/repo-location
export GOBLET_CONFIG_BASE="$GITHUB_WORKSPACE"

export GOBLET_RUN_FROM_CI=1
[ "$GOBLET_TEST_NO_CI" ] && unset GOBLET_RUN_FROM_CI

MOUNT_WORK_DIR=$(pwd)

exitError(){
  echo "::set-output name=error::'$1'"
  echo "::set-output name=result::fail"
  local STATUS="${1:-1}"
  exit "${STATUS}"
}

getENVValue() {
  local ENV_NAME="${1}"
  local FOUND_VAL="${2:-$3}"

  if [ "$FOUND_VAL" ]; then
    eval "export $ENV_NAME=$FOUND_VAL"
  fi
}

# ---- Step 0 - Set ENVs from inputs if they don't already exist
# Goblet Action specific ENVs
setRunEnvs(){

  getENVValue "GOBLET_TESTS_PATH" "${1}" "$GOBLET_TESTS_PATH"
  getENVValue "GIT_TOKEN" "${2}" $GIT_TOKEN
  getENVValue "GOBLET_TOKEN" "${3}" $GOBLET_TOKEN
  # TODO: Enable when goblet tokens are setup
  # [ -z "$GOBLET_TOKEN" ] && exitError "Goblet Token is required."

  # Alt Repo ENVs
  getENVValue "GIT_ALT_REPO" "${4}" "$GIT_ALT_REPO"
  getENVValue "GIT_ALT_BRANCH" "${5}" "$GIT_ALT_BRANCH"
  getENVValue "GIT_ALT_USER" "${6}" "$GIT_ALT_USER"
  getENVValue "GIT_ALT_EMAIL" "${7}" "$GIT_ALT_EMAIL"
  getENVValue "GIT_ALT_TOKEN" "${8}" "$GIT_ALT_TOKEN"

  # Goblet Test specific ENVs
  getENVValue "GOBLET_TEST_TYPE" "${9}" "$GOBLET_TEST_TYPE"
  getENVValue "GOBLET_TEST_RETRY" "${10}" "$GOBLET_TEST_RETRY"
  getENVValue "GOBLET_TEST_REPORT_NAME" "${11}" "$GOBLET_TEST_REPORT_NAME"
  getENVValue "GOBLET_TEST_TRACING" "${12}" "$GOBLET_TEST_TRACING"
  getENVValue "GOBLET_TEST_SCREENSHOT" "${13}" "$GOBLET_TEST_SCREENSHOT"
  getENVValue "GOBLET_TEST_VIDEO_RECORD" "${14}" "$GOBLET_TEST_VIDEO_RECORD"
  
  getENVValue "GOBLET_TEST_TIMEOUT" "${15}" "$GOBLET_TEST_TIMEOUT"
  getENVValue "GOBLET_TEST_CACHE" "${16}" "$GOBLET_TEST_CACHE"
  getENVValue "GOBLET_TEST_COLORS" "${17}" "$GOBLET_TEST_COLORS"
  getENVValue "GOBLET_TEST_WORKERS" "${18}" "$GOBLET_TEST_WORKERS"
  getENVValue "GOBLET_TEST_VERBOSE" "${19}" "$GOBLET_TEST_VERBOSE"
  getENVValue "GOBLET_TEST_OPEN_HANDLES" "${20}" "$GOBLET_TEST_OPEN_HANDLES"

  getENVValue "GOBLET_BROWSERS" "${21}" "$GOBLET_BROWSERS"
  getENVValue "GOBLET_BROWSER_SLOW_MO" "${22}" "$GOBLET_BROWSER_SLOW_MO"
  getENVValue "GOBLET_BROWSER_CONCURRENT" "${23}" "$GOBLET_BROWSER_CONCURRENT"
  getENVValue "GOBLET_BROWSER_TIMEOUT" "${24}" "$GOBLET_BROWSER_TIMEOUT"

  # Goblet App specific ENVs
  [ -z "$NODE_ENV" ] && export NODE_ENV=test
  [ -z "$DOC_APP_PATH" ] && export DOC_APP_PATH=/keg/tap
  [ -z "$GOBLET_APP_URL" ] && export GOBLET_APP_URL="$APP_URL"

  getENVValue "GOBLET_GIT_TOKEN" "$GIT_ALT_TOKEN" "$GIT_TOKEN"

}

# Clones an alternitive repo locally
cloneAltRepo(){
  cd $GOBLET_MOUNT_ROOT/goblet

  # If git user and email not set, use the current user from existing the git log
  [ -z "$GIT_ALT_USER" ] && export GIT_ALT_USER="$(git log --format='%ae' HEAD^!)"
  [ -z "$GIT_ALT_EMAIL" ] && export GIT_ALT_EMAIL="$(git log --format='%an' HEAD^!)"

  git config --local user.email "$GIT_ALT_USER"
  git config --local user.name "$GIT_ALT_EMAIL"

  # Clone the repo using the passed in token if it exists
  local GIT_CLONE_TOKEN="${GIT_ALT_TOKEN:-$GOBLET_GIT_TOKEN}"
  if [ "$GIT_CLONE_TOKEN" ]; then
    git clone https://$GIT_CLONE_TOKEN@$GIT_ALT_REPO
  else
    git clone https://$GIT_ALT_REPO
  fi

  # Navigate into the repo so we can get the pull path from (pwd)
  cd ./alt-repo

  # If using a diff branch from default, fetch then checkout from origin
  if [ "$GIT_ALT_BRANCH" ]; then
    git fetch origin
    git checkout -b $GIT_ALT_BRANCH origin/$GIT_ALT_BRANCH
  fi

  export GOBLET_CONFIG_BASE="$(pwd)"
}

# ---- Step 2 - Synmlink the workspace folder to the repos folder
setupWorkspace(){
  [ "$GIT_ALT_REPO" ] && cloneAltRepo "$@"

  echo ""
  logMsg "Repo mount is $GOBLET_CONFIG_BASE"
}

# ---- Step 4 - Run the tests
runTests(){
  logMsg "Running Tests..."
  # Goblet test run specific ENVs - customizable
  # Switch to the goblet dir and run the bdd test task
  cd /home/runner/tap


  local TEST_RUN_ARGS="--env $NODE_ENV --base $GOBLET_CONFIG_BASE"
  [ -z "$GOBLET_TEST_TYPE" ] && export GOBLET_TEST_TYPE="${GOBLET_TEST_TYPE:-bdd}"

  if [ "$GOBLET_TEST_TYPE" == "bdd" ]; then

    export GOBLET_TESTS_PATH="${GOBLET_TESTS_PATH:-$GOBLET_CONFIG_BASE}"
    TEST_RUN_ARGS="$TEST_RUN_ARGS --context $GOBLET_TESTS_PATH"

    # Add special handling for setting browsers option to auto set ---allBrowsers when not set
    if [ -z "$GOBLET_BROWSERS" ]; then
      TEST_RUN_ARGS="$TEST_RUN_ARGS --allBrowsers"
    elif  [ "$GOBLET_BROWSERS" == "all" ]; then
      TEST_RUN_ARGS="$TEST_RUN_ARGS --allBrowsers"
    else
      TEST_RUN_ARGS="$TEST_RUN_ARGS --browsers $GOBLET_BROWSERS"
    fi

    node ./tasks/runTask.js bdd run $TEST_RUN_ARGS
    local TEST_EXIT_STATUS=$?

    [ ${TEST_EXIT_STATUS} -ne 0 ] && export GOBLET_TESTS_RESULT="fail" || export GOBLET_TESTS_RESULT="pass"
    logMsg "Finished running tests for $GOBLET_TESTS_PATH"


  else
    logErr "Test type $GOBLET_TEST_TYPE not yet supported"
    exitError "1"
  fi

}

# ---- Step 6 - Output the result of the executed tests
setActionOutputs(){
  echo "::set-output name=result::$GOBLET_TESTS_RESULT"

  local GOBLET_TESTS_REPORT_PATH=$(jq -r -M .latest.$GOBLET_TEST_TYPE.report.path /home/runner/tap/temp/testMeta.json)
  echo "::set-output name=report-path::$GOBLET_TESTS_REPORT_PATH"

  local GOBLET_TESTS_VIDEO_PATH=$(jq -r -M .latest.$GOBLET_TEST_TYPE.artifacts.path /home/runner/tap/temp/testMeta.json)
  echo "::set-output name=video-path::$GOBLET_TESTS_VIDEO_PATH"
  
  local GOBLET_TESTS_VIDEO_PATH=$(jq -r -M .latest.$GOBLET_TEST_TYPE.artifacts.path /home/runner/tap/temp/testMeta.json)
  echo "::set-output name=trace-path::$GOBLET_TESTS_TRACE_PATH"
  
}

init() {(
  set -e
  setRunEnvs "$@"
  setupWorkspace "$@"
  runTests "$@"
  setActionOutputs "$@"
)}

init "$@"
EXIT_STATUS=$?

[ ${EXIT_STATUS} -ne 0 ] && exitError "$EXIT_STATUS"