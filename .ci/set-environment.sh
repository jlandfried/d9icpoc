#!/bin/bash
set -eo pipefail

#
# Before calling this script, set the following environent variables:
#
#   - CI_BRANCH: the branch being tested
#   - CI_BUILD_NUMBER: monotonically increasing build counter
#   - PR_NUMBER: pull request number (if job is from a pull request)
#
# Optionally:
#
#   - CI_PULL_REQUEST: URL to the current pull request; used to set PR_NUMBER
#   - DEFAULT_SITE: name of the repository; used to set TERMINUS_SITE
#
# Note that any environment variable given above is not set, then
# it will be assigned its value from the corresponding CircleCI
# environment variable.
#
CI_BRANCH=${CI_BRANCH:-$CIRCLE_BRANCH}
CI_BUILD_NUMBER=${CI_BUILD_NUMBER:-$CIRCLE_BUILD_NUM}
CI_PROJECT_NAME=${CI_PROJECT_NAME:-CIRCLE_PROJECT_REPONAME}

# Circle sets both $CIRCLE_PULL_REQUEST and $CI_PULL_REQUEST.
PR_NUMBER=${PR_NUMBER:-$CI_PULL_REQUEST}
PR_NUMBER=${PR_NUMBER##*/}

# Set up BASH_ENV if it was not set for us.
BASH_ENV=${BASH_ENV:-$HOME/.bashrc}

# Provide a default email address
GIT_EMAIL=${GIT_EMAIL:-ci-bot@pantheon.io}

# We will also set the default site name to be the same as the repository name.
DEFAULT_SITE=${DEFAULT_SITE:-$CI_PROJECT_NAME}

# By default, we will make the main branch master.
DEFAULT_BRANCH=${DEFAULT_BRANCH:-master}

# If we are on the default branch.
if [[ ${CI_BRANCH} == ${DEFAULT_BRANCH} ]] ; then
  # Use dev as the environment.
	DEFAULT_ENV=${DEFAULT_ENV:-dev}
else
  # Otherwise, name the environment after the CI build number.
	DEFAULT_ENV=ci-$CI_BUILD_NUMBER
fi

# If there is a PR number provided, though, then we will use it instead.
if [[ -n ${PR_NUMBER} ]] ; then
  DEFAULT_ENV="pr-${PR_NUMBER}"
fi

CI_PR_URL=${CI_PR_URL:-$CIRCLE_PULL_REQUEST}
CI_PROJECT_USERNAME=${CI_PROJECT_USERNAME:-$CIRCLE_PROJECT_USERNAME}
CI_PROJECT_REPONAME=${CI_PROJECT_REPONAME:-$CIRCLE_PROJECT_REPONAME}
TERMINUS_SITE=${TERMINUS_SITE:-$DEFAULT_SITE}
TERMINUS_ENV=${TERMINUS_ENV:-$DEFAULT_ENV}

# If any Pantheon environments are locked, users may provide a URL-encoded
# 'username:password' string in an environment variable to include the
# HTTP Basic Authentication.
MULTIDEV_SITE_BASIC_AUTH=${MULTIDEV_SITE_BASIC_AUTH:-$SITE_BASIC_AUTH}
DEV_SITE_BASIC_AUTH=${DEV_SITE_BASIC_AUTH:-$SITE_BASIC_AUTH}
TEST_SITE_BASIC_AUTH=${TEST_SITE_BASIC_AUTH:-$SITE_BASIC_AUTH}
LIVE_SITE_BASIC_AUTH=${LIVE_SITE_BASIC_AUTH:-$SITE_BASIC_AUTH}

# Prepare the Basic Authentication strings, appending the "@" sign if not empty.
MULTIDEV_SITE_BASIC_AUTH=${MULTIDEV_SITE_BASIC_AUTH:+"$MULTIDEV_SITE_BASIC_AUTH@"}
DEV_SITE_BASIC_AUTH=${DEV_SITE_BASIC_AUTH:+"$DEV_SITE_BASIC_AUTH@"}
TEST_SITE_BASIC_AUTH=${TEST_SITE_BASIC_AUTH:+"$TEST_SITE_BASIC_AUTH@"}
LIVE_SITE_BASIC_AUTH=${LIVE_SITE_BASIC_AUTH:+"$LIVE_SITE_BASIC_AUTH@"}

#=====================================================================================================================
# EXPORT needed environment variables
#
# Circle CI 2.0 does not yet expand environment variables so they have to be manually EXPORTed
# Once environment variables can be expanded this section can be removed
# See: https://discuss.circleci.com/t/unclear-how-to-work-with-user-variables-circleci-provided-env-variables/12810/11
# See: https://discuss.circleci.com/t/environment-variable-expansion-in-working-directory/11322
# See: https://discuss.circleci.com/t/circle-2-0-global-environment-variables/8681
# Bitbucket has similar issues:
# https://bitbucket.org/site/master/issues/18262/feature-request-pipeline-command-to-modify
#=====================================================================================================================
(
  echo 'export PATH=$PATH:$HOME/bin'
  echo "export PR_NUMBER=$PR_NUMBER"
  echo "export CI_BRANCH=$(echo $CI_BRANCH | grep -v '"'^\(master\|[0-9]\+.x\)$'"')"
  echo "export CI_BUILD_NUMBER=$CI_BUILD_NUMBER"
  echo "export DEFAULT_SITE='$DEFAULT_SITE'"
  echo "export CI_PR_URL='$CI_PR_URL'"
  echo "export CI_PROJECT_USERNAME='$CI_PROJECT_USERNAME'"
  echo "export CI_PROJECT_REPONAME='$CI_PROJECT_REPONAME'"
  echo "export DEFAULT_ENV='$DEFAULT_ENV'"
  echo 'export TERMINUS_HIDE_UPDATE_MESSAGE=1'
  echo "export TERMINUS_SITE='$TERMINUS_SITE'"
  echo "export TERMINUS_ENV='$TERMINUS_ENV'"
  echo "export DEFAULT_BRANCH='$DEFAULT_BRANCH'"
  # TODO: Reconcile with environment variables set by build:project:create
  echo 'export BEHAT_ADMIN_PASSWORD=$(openssl rand -base64 24)'
  echo 'export BEHAT_ADMIN_USERNAME=pantheon-ci-testing-$CI_BUILD_NUMBER'
  echo 'export BEHAT_ADMIN_EMAIL=no-reply+ci-$CI_BUILD_NUMBER@getpantheon.com'
  echo "export MULTIDEV_SITE_URL='https://${MULTIDEV_SITE_BASIC_AUTH}$TERMINUS_ENV-$TERMINUS_SITE.pantheonsite.io/'"
  echo "export DEV_SITE_URL='https://${DEV_SITE_BASIC_AUTH}dev-$TERMINUS_SITE.pantheonsite.io/'"
  echo "export TEST_SITE_URL='https://${TEST_SITE_BASIC_AUTH}test-$TERMINUS_SITE.pantheonsite.io/'"
  echo "export LIVE_SITE_URL='https://${LIVE_SITE_BASIC_AUTH}live-$TERMINUS_SITE.pantheonsite.io/'"
  echo "export ARTIFACTS_DIR='artifacts'"
  echo "export ARTIFACTS_FULL_DIR='/tmp/artifacts'"
) >> $BASH_ENV

# If a Terminus machine token and site name are defined
if [[ -n "$TERMINUS_MACHINE_TOKEN" && -n "$TERMINUS_SITE" ]]
then

  # Authenticate with Terminus
  terminus -n auth:login --machine-token="$TERMINUS_MACHINE_TOKEN" > /dev/null 2>&1

  # Use Terminus to fetch variables
  TERMINUS_SITE_UUID=$(terminus site:info $TERMINUS_SITE --field=id)

  # And add those variables to $BASH_ENV
  (
    echo "export TERMINUS_SITE_UUID='$TERMINUS_SITE_UUID'"
  ) >> $BASH_ENV
fi

source $BASH_ENV

echo 'Contents of BASH_ENV:'
cat $BASH_ENV
echo

# Avoid ssh prompting when connecting to new ssh hosts
mkdir -p $HOME/.ssh && echo "StrictHostKeyChecking no" >> "$HOME/.ssh/config"

# Configure the GitHub Oauth token if it is available
#if [ -n "$GITHUB_TOKEN" ]; then
#  composer -n config --global github-oauth.github.com $GITHUB_TOKEN
#fi

# Set up our default git config settings if git is available.
git config --global user.email "${GIT_EMAIL:-no-reply+ci-$CI_BUILD_NUMBER@getpantheon.com}"
git config --global user.name "CI Bot"
git config --global core.fileMode false

# Re-install the Terminus Build Tools plugin if requested
if [ -n $BUILD_TOOLS_VERSION ] && [ "$BUILD_TOOLS_VERSION" <> 'dev-master' ]; then
  echo "Install Terminus Build Tools Plugin version $BUILD_TOOLS_VERSION."
  echo "Note that it is NOT RECOMMENDED to define BUILD_TOOLS_VERSION, save in the Terminus Build Tools plugin tests themselves. All other tests should use the version bundled with the container."
  rm -rf ${TERMINUS_PLUGINS_DIR:-~/.terminus/plugins}/terminus-build-tools-plugin
  composer -n create-project --no-dev -d ${TERMINUS_PLUGINS_DIR:-~/.terminus/plugins} pantheon-systems/terminus-build-tools-plugin:$BUILD_TOOLS_VERSION
fi
