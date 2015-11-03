# source this and dont run it
# this can change:
#   BUNDLE_GEMFILE
#   BUNDLE_WITHOUT
#   PWD

echo "gem: --no-ri --no-rdoc --no-document" > ~/.gemrc

# determine if we should even run this matrix entry

ruby build_tools/johnny_five.rb \
        --component ${TEST_SUITE:-$GEM} \
        --config build_tools/config_two.rb || touch .skip-ci

if [[ -f ${TRAVIS_BUILD_DIR}/.skip-ci ]] ; then
  # change into a directory with minimal environment
  # this will NOP the rest of the build
  # cd build_tools
  :
elif [[ -n "${GEM}" ]] ; then
  cd gems/${GEM}
else
  travis_retry gem install bundler -v ">= 1.8.4"
  [[ -z "${SPA_UI}" ]] || nvm install 0.12

  [[ -f certs/v2_key.dev ]] && cp certs/v2_key.dev certs/v2_key
  echo "1" > REGION
  cp config/database.pg.yml config/database.yml
  psql -c "CREATE USER root SUPERUSER PASSWORD 'smartvm';" -U postgres
  export BUNDLE_WITHOUT=development
fi
export BUNDLE_GEMFILE=${PWD}/Gemfile
