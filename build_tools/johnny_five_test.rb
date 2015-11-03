require "minitest/autorun"

require_relative 'johnny_five'

class TestJohnnyFive < Minitest::Test
  def johnny
    @johnny ||= JohnnyFive.new
  end

  def test_parse_pr
    johnny.parse(["--verbose", "#{__dir__}/config_two.rb"],
      "TRAVIS_BRANCH" => "master", 
      "TRAVIS_PULL_REQUEST" => "1",
      "TRAVIS_COMMIT_RANGE" => "9e59113ba4...d19278a8f6"
    )

    assert_equal "master", johnny.sherlock.branch ##
    assert_equal "1", johnny.sherlock.pr
    assert_equal true, johnny.sherlock.pr?
    assert_equal "9e59113ba4...d19278a8f6", johnny.files.range
  end

  def test_parse_master
    johnny.parse(["--verbose", "#{__dir__}/config_two.rb"],
      "TRAVIS_BRANCH" => "master", 
      "TRAVIS_PULL_REQUEST" => "false",
      "TRAVIS_COMMIT_RANGE" => "9e59113ba4...9130838e79"
    )

    assert_equal "master", johnny.sherlock.branch
    assert_equal "false", johnny.sherlock.pr
    assert_equal false, johnny.sherlock.pr?
    assert_equal "9e59113ba4...9130838e79", johnny.files.range
  end
end

#TRAVIS_BRANCH="test_branch_merge" TRAVIS_PULL_REQUEST="1" TRAVIS_COMMIT="d19278a8f6" TRAVIS_COMMIT_RANGE="9e59113ba4...d19278a8f6" ruby build_tools/johnny_five.rb
