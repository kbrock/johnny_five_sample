#!/usr/bin/env ruby

# Get files or commits for a given pull request / commit
class TravisParser
  # @return <String> pull request number ("false" if this is a branch)
  attr_accessor :pr
  # branch being built (for a pr, target branch / typically master)
  attr_accessor :branch
  attr_accessor :commit_range

  def parse(_argv = ARGV, env = ENV)
    @pr     = env['TRAVIS_PULL_REQUEST']
    @branch = env['TRAVIS_BRANCH']
    @commit_range = env['TRAVIS_COMMIT_RANGE'] || ""
  end

  def first_commit
    commit_range.split("...").first || ""
  end

  def pr?
    @pr != "false"
  end

  def commit_range?
    first_commit != ""
  end

  def single_commit?
    !commit_range.include?("...")
  end

  def file_ref
    if !commit_range? # havent seen this
      "FETCH_HEAD^...FETCH_HEAD"
    elsif single_commit? # havent seen this
      "#{first_commit}^...#{first_commit}"
    else
      commit_range
    end
  end

  def file_refs
    [file_ref]
  end

  def files(ref = file_ref)
    #git("diff --name-only #{ref}").split("\n").uniq.sort
    git("log --name-only --pretty=\"format:\" #{ref}", "").split("\n").uniq.sort
  end

  def commits(ref = file_ref)
    git("log --oneline --decorate #{ref}", "").split("\n")
  end

  def inform(component = "build")
    puts "#{pr? ? "PR" : "  "} BRANCH    : #{branch}"
    puts "COMMIT_RANGE : #{commit_range}"
    puts "component    : #{component}"
    puts "file ref     : #{file_ref}"
  end

  # pass in &:commits or &:files
  def compare
    puts
    puts "COMMITS:"
    file_refs.each do |fr|
      puts "======="
      puts "#{fr}"
      puts yield(fr).map { |c| "  - #{c}" }.join("\n")
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
    file_list.compare_files
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
