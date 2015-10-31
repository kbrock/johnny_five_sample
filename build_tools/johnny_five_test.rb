require "minitest/autorun"

require_relative 'johnny_five'

class TestJohnnyFive < Minitest::Test
  def parser
    @parser ||= JohnnyFive::Travis.new
  end

  def test_parse_pr
    parser.parse(%w(-v),
      "TRAVIS_BRANCH" => "master", 
      "TRAVIS_PULL_REQUEST" => "1",
      "TRAVIS_COMMIT_RANGE" => "9e59113ba4...d19278a8f6"
    )

    assert_equal "master", parser.branch
    assert_equal "1", parser.pr
    assert_equal true, parser.pr?
    assert_equal "9e59113ba4...d19278a8f6", parser.range
  end

  def test_parse_master
    parser.parse(%w(-v),
      "TRAVIS_BRANCH" => "master", 
      "TRAVIS_PULL_REQUEST" => "false",
      "TRAVIS_COMMIT_RANGE" => "9e59113ba4...9130838e79"
    )

    assert_equal "master", parser.branch
    assert_equal "false", parser.pr
    assert_equal false, parser.pr?
    assert_equal "9e59113ba4...9130838e79", parser.range
  end
end

#TRAVIS_BRANCH="test_branch_merge" TRAVIS_PULL_REQUEST="1" TRAVIS_COMMIT="d19278a8f6" TRAVIS_COMMIT_RANGE="9e59113ba4...d19278a8f6" ruby build_tools/johnny_five.rb
