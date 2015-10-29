#!/usr/bin/env ruby

# see also https://github.com/travis-ci/travis-ci/issues/5007
# env vars: http://docs.travis-ci.com/user/environment-variables/#Default-Environment-Variables
# base code: https://github.com/TechEmpower/FrameworkBenchmarks/blob/master/toolset/run-ci.py#L53
class TravisParser
  # @return <String> pull request number ("false" if this is a branch)
  attr_accessor :pr
  # branch being built (for a pr, target branch / typically master)
  attr_accessor :branch
  attr_accessor :commit
  attr_accessor :commit_range

  def initialize(options = {})
    options.each do |n, v|
      public_send("#{n}=", v)
    end
  end

  def parse(_argv = ARGV, env = ENV)
    @pr     = env['TRAVIS_PULL_REQUEST']
    @branch = env['TRAVIS_BRANCH']
    @commit = env['TRAVIS_COMMIT']
    @commit_range = env['TRAVIS_COMMIT_RANGE'] || ""
  end

  def first_commit
    commit_range.split("...").first || ""
  end

  def last_commit_alt
    commit_range.split("...").last || ""
  end

  def last_commit
    @last_commit ||= git("rev-list -n 1 FETCH_HEAD^2")
  end

  def pr?
    @pr != "false"
  end

  def commit_range?
    first_commit != ""
  end

  # There is only one commit in the pull request so far,
  # or Travis-CI is not yet passing the commit range properly
  # for pull requests. We examine just the one commit using -1
  #
  # On the oddball chance that it's a merge commit, we pray
  # it's a merge from upstream and also pass --first-parent
  def single_commit?
    commit_range? && (first_commit == last_commit)
  end

  def file_refs
    if pr?
      if !commit_range?
        # use the filelist from auto merge
        # unfortunatly, pushes to a PR will immediately affect a running job.
        [
          "-m --first-parent -1 FETCH_HEAD",
          "-m --first-parent FETCH_HEAD~1...FETCH_HEAD",
        ]
      elsif single_commit?
        [
          "#{commit_range}",
          "#{last_commit}^...#{last_commit}",
          "-m --first-parent -1 #{last_commit_alt}",
          "-m --first-parent -1 #{last_commit}",
          "-m --first-parent #{commit_range}",
          "#{last_commit_alt}^...#{last_commit_alt}",
        ]
      else
        [
          "#{commit_range}",
          "--first-parent #{first_commit}...#{last_commit}",
          "--first-parent #{first_commit}...#{last_commit_alt}",
          "--first-parent #{commit_range}",
        ]
      end
    else
        # Three main scenarios to consider
        #  - 1 One non-merge commit pushed to master
        #  - 2 One merge commit pushed to master (e.g. a PR was merged).
        #      This is an example of merging a topic branch
        #  - 3 Multiple commits pushed to master
        #
        #  1 and 2: show changes brought into master for the one commit.
        #  ==> `git log -1 COMMIT`.
        #  ==> `--first-parent -m` handles merges of sub-topic branchs
        #
        #  3: compare all merged into master
        #  ==> to include sub merges, best to not use `--first-parent`
        #  since sub merges is not common and difficult to distinguish
        #  so punting. (we're building all of master anyway - so no biggie)
      [
        "#{commit_range}",
        "--first-parent -m #{commit_range}",
      ]
    end
  end

  def changed_files(ref = file_refs.first)
    #git("diff --name-only #{ref}").split("\n").uniq.sort
    git("log --name-only --pretty=\"format:\" #{ref}", "").split("\n").uniq.sort
  end

  def commits(ref = file_refs.first)
    git("log --oneline --decorate #{ref}", "").split("\n")
  end

  def inform(component = "build")
    if pr?
      puts "PR           : #{branch}"
      puts "COMMIT_RANGE : #{commit_range}" #if single_commit? || !commit_range?
      puts "first_commit : #{first_commit}"
      puts "last_commit  : #{last_commit_alt} : git: #{last_commit if last_commit_alt != last_commit}"
    else
      puts "BRANCH       : #{branch}"
      puts "first_commit : #{first_commit}"
      puts "last_commit  : #{last_commit_alt} (branch has no alt)"
    end
    puts "FETCH_HEAD   : #{git("rev-parse FETCH_HEAD   2>/dev/null")} (debug)"
    puts "FETCH_HEAD   : #{git("rev-parse FETCH_HEAD^1 2>/dev/null")} (debug)"
    puts "FETCH_HEAD^2 : #{git("rev-parse FETCH_HEAD^2 2>/dev/null")} (debug)"
    puts "COMMIT       : #{commit || "EMPTY"}" if !commit || commit != last_commit_alt
    puts "component    : #{component}"
    puts "file ref     : #{file_refs.first}"
  end

  def compare_commits
    puts
    puts "COMMITS:"
    file_refs.each do |fr|
      puts "======="
      puts "#{fr}"
      #puts "======="
      puts commits(fr).map { |c| "  - #{c}" }.join("\n")
    end
    puts "======="
    puts
  end

  def compare_files
    puts "FILES:"
    puts changed_files.join("\n")
    file_refs.each do |fr|
      puts "======="
      puts "#{fr}"
      #puts "======="
      puts changed_files(fr).map { |c| "  - #{c}" }.join("\n")
    end
    puts "======="
    puts
  end

  private

  def git(args, default_value = nil)
    # puts "git #{args}" if verbose
    ret = `git #{args} 2> /dev/null`.chomp
    $?.to_i == 0 ? ret : default_value
  end
end

class JohnnyFive
  attr_accessor :component
  attr_accessor :touch
  attr_accessor :file_list

  def initialize
    @file_list = TravisParser.new
  end

  def parse(argv = ARGV, env = ENV)
    self.touch     = argv.detect { |arg| arg == "-t" } || true # always create file
    self.component = env["TEST_SUITE"] || env["GEM"]
    file_list.parse(argv, env)
    self
  end

  def run
    file_list.inform(component)
    file_list.compare_commits
    run_it, reason = determine_course_of_action
    skip!(reason) unless run_it
  end

  # logic
  def skip!(reason)
    puts "skipping: #{reason}"
  end

  def determine_course_of_action
    #cfg.build :pr => false, :branch => "master" # always build master
    if !file_list.pr?
      if file_list.branch == "master"
        [true, "building non-PR, branch: master"]
      else
        [false, "skipping non-PR, branch: (not master)"]
      end
    #cfg.build :pr => true, :match => :component, :suffix => "-spec"
    else
      target_component = "#{component}#{"-spec"}"
      if triggered?(target_component)
        [true, "building PR, changed component"]
      else
        [false, "skipping PR, non-triggered component"]
      end
    end
  end

  def triggered?(target_name)
    # in the filelist - determine which targets were triggered
    #return true if we can find target in there (or :all came back)
    true
  end

  def self.instance
    @instance ||= new
  end

  # dsl


  # main entry

  def self.run(argv, env)
    instance.parse(argv, env).run
  end
end

if __FILE__ == $PROGRAM_NAME
  $stdout.sync = true
  $stderr.sync = true

  JohnnyFive.run(ARGV, ENV)
end
