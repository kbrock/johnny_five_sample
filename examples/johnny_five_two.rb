#!/usr/bin/env ruby

class TravisParser
  attr_accessor :verbose

  # ENV['TRAVIS_PULL_REQUEST']
  # pull request number ("false" if this is a branch)
  attr_accessor :pr
  # ENV["TRAVIS_BRANCH"]
  # branch being built (for a pr this is the target branch, typicaly master)
  attr_accessor :branch
  # ENV['TRAVIS_COMMIT']
  # The commit that the current build is testing
  attr_accessor :commit
  # ENV['TRAVIS_COMMIT_RANGE']
  # The range of commits
  attr_accessor :commit_range

  attr_accessor :first_commit # calculated from comit_range
  attr_accessor :last_commit  # calculated from git (maybe use commit_range?)

  def initialize(options = {})
    @verbose = true
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

  def pr?
    @pr != "false"
  end

  def first_commit
    @first_commit ||= commit_range.split("...").first || ""
  end

  def last_commit_alt
    @last_commit_alt ||= commit_range.split("...").last || ""
  end

  def last_commit
    @last_commit ||= git("rev-list -n 1 FETCH_HEAD^2")
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
          "-m --first-parent FETCH_HEAD~1...FETCH_HEAD"
        ]
      elsif single_commit?
        [
          "-m --first-parent -1 #{last_commit}",
          "-m --first-parent #{commit_range}",
          "--first-parent #{last_commit}^...#{last_commit}"
        ]
      else
        # In case they merged in upstream, we only care about the first
        # parent. For crazier merges, we hope
        [
          "--first-parent #{first_commit}...#{last_commit}",
          "--first-parent #{first_commit}...#{last_commit_alt}",
          "--first-parent #{commit_range}"
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
        "--first-parent -m #{commit_range}"
      ]
    end
  end

  def changed_files(ref = file_refs.first)
    #git("diff --name-only #{ref}").split("\n").uniq.sort
    git("log --name-only --pretty=\"format:\" #{ref}").split("\n").uniq.sort
  end

  def commits(ref = file_refs.first)
    git("log --oneline --decorate #{ref}").split("\n")
  end

  def inform(component = "build")
    if pr?
      puts "PR           : #{branch}"
      puts "COMMIT_RANGE : #{commit_range}" if single_commit? || !commit_range?
      puts "first_commit : #{first_commit}"
      puts "last_commit  : #{last_commit} #{last_commit_alt if last_commit_alt != last_commit}"
    else
      puts "BRANCH       : #{branch}"
      puts "first_commit : #{first_commit}"
      puts "last_commit  : #{last_commit_alt} (branch has no alt)"
    end
    puts "FETCH_HEAD     : #{git("rev-parse FETCH_HEAD   2>/dev/null")} (debug)"
    puts "FETCH_HEAD     : #{git("rev-parse FETCH_HEAD^1 2>/dev/null")} (debug)"
    puts "FETCH_HEAD^2   : #{git("rev-parse FETCH_HEAD^2 2>/dev/null")} (debug)"
    puts "COMMIT         : #{commit}"
    puts "component      : #{component}"
    puts "file ref       : #{file_refs.first}"
  end

  def compare_commits
    puts
    puts "COMMITS:"
    puts "======="
    file_refs.each do |fr|
      puts "#{fr}"
      puts commits(fr)
      puts "======="
    end
    puts
  end

  def compare_files
    puts "FILES:"
    puts "======="
    puts changed_files.join("\n")
    file_refs.each do |fr|
      puts "#{fr}"
      puts changed_files(fr).join("\n")
      puts "======="
    end
    puts
  end

  def debug(msg)
    $stderr.puts "DEBUG: #{msg}" # if verbose?
  end

  private

  def git(args)
    # puts "git #{args}" if verbose
    ret = `git #{args}`.chomp
    ret if $?.to_i == 0
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
    file_list.compare_commits
    # file_list.compare_files
  end

  def changed_files
    file_list.changed_files
  end

  def parse(argv, env)
    parse(argv, env)
    self
  end

  # actions

  def skip!(justification = "NONE")
    if justification
      skip_file = "#{ENV["TRAVIS_BUILD_DIR"]}/.skip-ci"
      justification = "SKIPPING: #{justification}\n"
      $stderr.puts "==> #{justification} <=="
      File.write(skip_file, justification)
    else
      $stderr.puts "*** building ***"
    end
  end

  def run
    inform
    run_it, reason = determine_course_of_action
    skip!(reason) unless run_it
  end

  def self.run(argv, env)
    instance.parse(argv, env).run
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

  def debug(msg)
    $stderr.puts "DEBUG: #{msg}" # if verbose?
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

  def skip(options)
  end

  def build(options)
  end

  def self.config
    yield instance
  end
end

if __FILE__ == $PROGRAM_NAME
  $stdout.sync = true
  $stderr.sync = true

  JohnnyFive.config do |cfg|
    cfg.file "Gemfile",                        %w(controllers models), :exact => true
    cfg.file "app/{assets,controllers,views}", "controllers"
    cfg.file "app/models",                     "models", :ext => ".rb"
    cfg.file "app/helpers",                    "controllers", :ext => ".rb"
    cfg.file "bin",                            :none
    cfg.file "build_tools",                    :all # temporary, switch to :none when done
    cfg.file "gems/one",                       "one", :except => %{gems/one/test}
    cfg.file "public",                         "ui"
    cfg.file "vendor",                         "ui"

    cfg.test "test/{controllers,views}",       "controllers-spec", :ext => "_spec.rb"
    cfg.test "test/fixtures",                  "models"
    cfg.test "test/helpers",                   "controllers-spec", :ext => "_spec.rb"
    cfg.test "test/integration",               "ui-spec", :ext => "_spec.rb"
    cfg.test "test/models",                    "models-spec", :ext => "_spec.rb"
    cfg.test "test/test_helper.rb",            :all, :exact => true

    cfg.trigger "controllers",                 "ui"
    cfg.trigger "models",                      "controllers"
    cfg.trigger "one",                         %(controllers models)

    cfg.trigger "controllers",                 "controllers-spec"
    cfg.trigger "models",                      "models-spec"
    cfg.trigger "one",                         "one-spec"
    cfg.trigger "ui",                          "ui-spec"

    cfg.build :pr => false, :branch => "master" # always build master
    # always build a pr that matches the component-spec
    cfg.build :pr => true, :match => :component, :suffix => "-spec"
    # cfg.build :default
    # cfg.error :default
    cfg.skip :default
  end

  JohnnyFive.run(ARGV, ENV)

  private
    # http://stackoverflow.com/questions/11276909/how-to-convert-between-a-glob-pattern-and-a-regexp-pattern-in-ruby
    def glob_to_regex(str)
      in_curlies = 0
      escaping = false
      str.split('').map do |char|
        if escaping
          escaping = false
          char
        else
          case char
          when '*'  then ".*"
          when "?"  then "."
          when "."  then "\\."
          when "{"  then in_curlies += 1 ; "("
          when "}"  then in_curlies > 0 ? ( in_curlies -= 1 ; ")" ) : char
          when ","  then in_curlies > 0 ? "|" : char
          when "\\" then escaping = true ; "\\"
          else             char
          end
        end
      end.join
    end

end
