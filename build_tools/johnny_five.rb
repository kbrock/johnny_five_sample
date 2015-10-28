#!/usr/bin/env ruby

# see also https://github.com/travis-ci/travis-ci/issues/5007

class TravisParser
  attr_accessor :verbose
  # ENV['TRAVIS_PULL_REQUEST']
  # PRs:     The pull request number
  # non PRs: "false"
  attr_accessor :pr
  # ENV["TRAVIS_BRANCH"]
  # PRs:     name of the branch targeted by PR (typically "master")
  # non PRs: name of the branch currently being built
  attr_accessor :branch
  # ENV['TRAVIS_COMMIT']
  # The commit that the current build is testing
  attr_accessor :commit
  # ENV['TRAVIS_COMMIT_RANGE']
  # The range of commits that were included in the push or pull request
  attr_accessor :commit_range
  # text before "..." in 
  attr_accessor :first_commit # calculated from comit_range
  attr_accessor :last_commit # calculated from git

  alias pr? pr

  def initialize(verbose = true)
    @verbose = true
  end

  def parse(_argv = ARGV, env = ENV)
    @pr     = env['TRAVIS_PULL_REQUEST'] != "false"
    @branch = env['TRAVIS_BRANCH']
    @commit = env['TRAVIS_COMMIT']
    @commit_range = env['TRAVIS_COMMIT_RANGE'] || ""
  end

  def first_commit
    @first_commit ||= commit_range.split("...").first || ""
  end

  def last_commit
    # @last_commit ||= commit_range.split("...").last || ""
    @last_commit ||= git("rev-list -n 1 FETCH_HEAD^2").chomp
  end

  def file_ref
    if pr?
      if first_commit == ""
        # Travis-CI is not yet passing a commit range for pull requests
        # so we must use the auto merge's changed file list. This has the
        # negative effect that new pushes to the PR will immediately
        # start affecting any new jobs, regardless of the build they are on
        debug("No first commit, using Github's auto merge commit")
        "--first-parent -1 -m FETCH_HEAD"
      elsif first_commit == last_commit
        # There is only one commit in the pull request so far,
        # or Travis-CI is not yet passing the commit range properly
        # for pull requests. We examine just the one commit using -1
        #
        # On the oddball chance that it's a merge commit, we pray
        # it's a merge from upstream and also pass --first-parent
        debug("Only one commit in range, examining #{last_commit}")
        "-m --first-parent -1 #{last_commit}"
      else
        # In case they merged in upstream, we only care about the first
        # parent. For crazier merges, we hope
        "--first-parent #{first_commit}...#{last_commit}"
      end
    else
      debug('I am not testing a pull request')
        # Three main scenarios to consider
        #  - 1 One non-merge commit pushed to master
        #  - 2 One merge commit pushed to master (e.g. a PR was merged).
        #      This is an example of merging a topic branch
        #  - 3 Multiple commits pushed to master
        #
        #  1 and 2 are actually handled the same way, by showing the
        #  changes being brought into to master when that one commit
        #  was merged. Fairly simple, `git log -1 COMMIT`. To handle
        #  the potential merge of a topic branch you also include
        #  `--first-parent -m`.
        #
        #  3 needs to be handled by comparing all merge children for
        #  the entire commit range. The best solution here would *not*
        #  use --first-parent because there is no guarantee that it
        #  reflects changes brought into master. Unfortunately we have
        #  no good method inside Travis-CI to easily differentiate
        #  scenario 1/2 from scenario 3, so I cannot handle them all
        #  separately. 1/2 are the most common cases, 3 with a range
        #  of non-merge commits is the next most common, and 3 with
        #  a range including merge commits is the least common, so I
        #  am choosing to make our Travis-CI setup potential not work
        #  properly on the least common case by always using
        #  --first-parent

        # Handle 3
        # Note: Also handles 2 because Travis-CI sets COMMIT_RANGE for
        # merged PR commits
      "--first-parent -m #{commit_range}"
    end

    # Handle 1
    # "--first-parent -m -1 #{commit}"
  end

  def changed_files
    @changed_files ||= git("log --name-only --pretty=\"format:\" #{file_ref}").split("\n").uniq
  end

  def inform(component = "build")
    if pr?
      puts "PR    BRANCH: #{branch}"
      puts "COMMIT_RANGE: #{commit_range}"
      puts "first_commit: #{first_commit}"
      puts "last_commit : #{last_commit}"
    else
      puts "merge into master (#{branch})"
      puts "COMMIT_RANGE: #{commit_range}"
    end
    puts "COMMIT      : #{commit}"
    puts "component   : #{component}"
    puts "file ref    : #{file_ref}"
    if verbose
      puts "CHANGED FILES:"
      puts "---"
      puts changed_files.uniq.sort.join("\n")
      puts "---"
    end
  end

  def debug(msg)
    $stderr.puts "DEBUG: #{msg}" # if verbose?
  end

  private

  def git(args)
    puts "git #{args}" if verbose
    `git #{args}`
  end
end

class JohnnyFive
  SKIP_FILE=".skip-ci"

  attr_accessor :component
  attr_accessor :verbose
  attr_accessor :touch
  alias verbose? verbose

  def parse(argv = ARGV, env = ENV)
    self.verbose   = argv.detect { |arg| arg == "-v" } || true # always verbose for now
    self.touch     = argv.detect { |arg| arg == "-t" } || true # always create file
    self.component = env["TEST_SUITE"] || env["GEM"]
    file_list.parse(argv, env)
  end

  def verbose=(val)
    @verbose = val
    file_list.verbose = val
  end

  def file_list
    @file_list ||= TravisParser.new
  end

  def inform
    file_list.inform(component)
  end

  def changed_files
    file_list.changed_files
  end

  def parse(argv, env)
    file_list.parse(env)
    self
  end

  # actions

  def skip(justification = nil)
    justification = "SKIPPING: #{justification}\n"
    puts justification
    File.write(SKIP_FILE, justification)
  end

  def run
    inform
    #skip("Im being trigger happy") if pr?
  end

  def self.run(argv, env)
    instance.parse(argv, env).run
  end

  ## configuration DSL

  def self.instance
    @instance ||= new
  end

  # a file that triggers 
  def file(glob, target, options = nil)
  end

  alias :test :file

  def trigger(src_target, dependent_target)
  end

  def self.config
    yield instance
  end
end

if __FILE__ == $PROGRAM_NAME
  JohnnyFive.config do |cfg|
    cfg.file "Gemfile",                        %w(controllers models), :exact => true
    cfg.file "app/{assets,controllers,views}", "controllers"
    cfg.file "app/models",                     "models"
    cfg.file "app/helpers",                    "controllers"
    cfg.file "{bin,build_tools}",              :none
    cfg.file "gems/one",                       "one", :except => %{gems/one/test}
    cfg.file "public",                         "controllers"
    cfg.file "vendor",                         "controllers"

    cfg.test "test/{controllers,views}",       "controllers-spec", :ext => "_spec.rb"
    cfg.test "test/fixtures",                  %w(models)
    cfg.test "test/helpers",                   "controllers-spec"
    cfg.test "test/integration",               "controllers-spec"
    cfg.test "test/models",                    "models-spec"
    cfg.test "test/test_helper.rb",            :all

    cfg.trigger "models",                      "controllers"
    cfg.trigger "one",                         %(controllers models)
  end

  JohnnyFive.run(ARGV, ENV)
end
