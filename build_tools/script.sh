#
if [[ -f "${TRAVIS_BUILD_DIR}/.skip-ci" ]] ; then
  echo "skipping build"
else
  bundle exec rake ${TEST_SUITE+test:$TEST_SUITE}
fi
