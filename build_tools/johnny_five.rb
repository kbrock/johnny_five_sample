#!/usr/bin/env ruby

require 'forwardable'
require 'optionparser'

class JohnnyFive
  VERSION = "0.0.4"

  class GitFileList
    include Enumerable
    # @return [String] the commits that have changed for this build (e.g.: first_commit...last_commit)
    attr_accessor :range

    # @return [String] commit range (e.g.: begin...end commit)
    def range
      if @range == "" || @range.nil?
        "FETCH_HEAD^...FETCH_HEAD"
      elsif !@range.include?("...")
        "#{@range}^...#{@range}"
      else
        @range
      end
    end

    def each(&block)
      files.each(&block)
    end

    def files
      git("log --name-only --pretty=\"format:\" #{range}").split("\n").uniq.sort
    end

    def commits
      git("log --oneline --decorate #{range}").split("\n")
    end

    private

    def git(args, default_value = "")
      ret = `git #{args} 2> /dev/null`.chomp
      $CHILD_STATUS.to_i == 0 ? ret : default_value
    end
  end

  class Rules
    def initialize
      @target = Hash.new { |h, k| h[k] = [] }
    end

    def []=(name, value)
      (name.kind_of?(Array) ? name : [name]).each { |n| @target[n] << value }
    end

    def [](names) # rule["name"] << won't work
      (names.kind_of?(Array) ? names : [names]).flat_map { |name| @target[name] }
    end

    def values
      @target.values.flatten
    end

    # convert a glob to a regular expression
    def self.glob2regex(glob, _options = {})
      return glob if glob.kind_of?(Regexp)

      Regexp.new(glob.gsub(/([{},.]|\*\*\/\*|\*\*\/|\*)/) do
        case $1
        when '**/*' then '.*'   # directory and file match
        when '*'    then '[^/]*' # file match
        when '**/'  then '.*/'   # directory match
        when '{'    then '(?:'   # grouping of filenames
        when '}'    then ')'     # end grouping of names
        when ','    then '|'     # or for grouping
        when '.'    then '\.'    # dot in filename
        end
      end)
    end
  end

  class RuleList
    def initialize
      @basic_rules        = Rules.new
      @shallow_rules      = Rules.new
      @basic_dependencies = Rules.new
    end

    # @return [Hash<String,Array<Regexp>] the files (value) that trigger a target (key)
    attr_accessor :shallow_rules
    # @return [Hash<String,Array<Regexp>] the files (galue) that trigger a target (key) and dependencies
    attr_accessor :basic_rules
    # @return [Hash<String,Array<String>] the targets (value) that trigger a target (key)
    attr_accessor :basic_dependencies

    # @param target [String]
    # @return [Array<Regexp>] rules for all these targets
    def [](target)
      (basic_rules[dependencies(target)] + shallow_rules[target]).uniq.compact
    end

    # @return [Array<String>] list of all targets and dependent targets
    def dependencies(target)
      targets = [target, :all]
      count = 0
      # keep doing this until we stop adding some
      while count != targets.size
        count = targets.size
        targets += basic_dependencies[targets]
        targets.compact!
        targets.uniq!
      end
      targets
    end

    # @return [Regexp] rule to match every file that is covered by a rule (for sanity checks)
    def every
      Regexp.union((basic_rules.values + shallow_rules.values).uniq)
    end
  end

  ########### FOLD ###########

  # uses facts to deduce a plan
  class Sherlock
    extend Forwardable

    def initialize(files, rules)
      @files = files
      @rules = rules
      @branches = []
    end

    # @return [String] branch being built (e.g.: master)
    attr_accessor :branch
    # @return [Array<String>|Nil] For a non-PR, branches that will trigger a build (all others will be ignored)
    attr_accessor :branches
    # @return [Boolean] true to check all files on the filesystem against rules
    attr_accessor :check
    # @return [String] component being built
    attr_accessor :component
    # @return [String] pull request number (e.g.: "555" or "false" for a branch)
    attr_accessor :pr
    # @return [Boolean] true to show verbose messages
    attr_accessor :verbose

    attr_accessor :files, :rules

    def pr?
      pr != "false"
    end

    def branch_match?
      branch.nil? || branch.empty? || branches.empty? || branches.include?(branch)
    end

    # @return [Boolean] true if the changed files trigger this target
    def triggered?(target)
      return true if component.nil? || component.empty?
      list("DETECT:") { @rules.dependencies(target) } if verbose
      list("REGEX:") { @rules[target] } if verbose || check
      regexp = Regexp.union(@rules[target])
      files.detect { |fn| regexp.match(fn) }.tap { |fn| puts "build triggered by change to file #{fn}" if fn }
    end

    # main logic to determine what to do
    def deduce
      if pr?
        if triggered?(component)
          [true, "building PR for #{component || "none specified"}"]
        else
          [false, "skipping PR for unchanged: #{component}"]
        end
      else
        if branch_match?
          [true, "building branch: #{branch || "none specified"}"]
        else
          [false, "skipping branch: #{branch} (not #{branches.join(", ")})"]
        end
      end
    end

    def inform
      puts "#{pr? ? "PR" : "  "} BRANCH    : #{branch}"
      puts "COMPONENT    : #{component}"
      puts "COMMIT_RANGE : #{files.range}"
      list("COMMITS") { files.commits }
      list("FILES") { files } if verbose
      self
    end

    def sanity_check
      all_files = every_file
      all_rules = rules.every
      list("UNCOVERED:", false) { all_files.select { |fn| !all_rules.match(fn) } }
    end

    def run
      inform
      sanity_check if check
      run_it, reason = deduce
      unless run_it
        puts "==> #{reason} <=="
        exit(1)
      end
    end

    private

    def list(name, always_display = true)
      entries = yield
      if always_display || !entries.empty?
        puts "======="
        puts "#{name}"
        puts entries.map { |fn| " - #{fn}" }
        puts
      end
    end

    # @return [Array<String>] all files in the current directory
    def every_file
      Dir['**/*'].select { |fn| File.file?(fn) } + Dir['.[a-z]*']
    end
  end

  # Parser for the command line
  class OptSetter
    def initialize(opts, model, env)
      @opts  = opts
      @model = model
      @env = env
    end

    def opt(value, *args)
      # support environment variable being specified
      unless args[0].start_with?("-")
        env = args.shift
        ev = @env[env]
        @model.send("#{value}=", ev) if ev
        args.last << " (#{env}=#{ev || "<not set>"})"
      end
      @opts.on(*args) { |v| @model.send("#{value}=", v) }
    end
  end

  # Configuration file Translator
  class DslTranslator
    extend Forwardable

    def initialize(main, sherlock, files, rules)
      @main = main
      @sherlock = sherlock
      # @files = files
      # @rules = rules
    end

    attr_reader :sherlock, :main
    def_delegators :sherlock, :branch=, :branches, :branches=, :check=, :component=, :verbose=, :rules, :files
    def_delegators :rules, :basic_dependencies, :basic_rules, :shallow_rules
    def_delegators :files, :range=

    def suite(name)
      @suite = name
      yield self
    end

    # add a file that triggers this rule and all dependencies
    def file(glob)
      basic_rules[@suite] = Rules.glob2regex(glob)
    end

    # add a file that triggers this rule (but not dependencies)
    def test(glob)
      shallow_rules[@suite] = Rules.glob2regex(glob)
    end

    # add a dependency between 2 rules
    def trigger(target)
      basic_dependencies[@suite] = target
    end
  end

  attr_reader :sherlock, :files, :rules

  def initialize
    @files = GitFileList.new
    @rules = RuleList.new
    @sherlock = Sherlock.new(@files, @rules)
  end

  def parse(argv, env)
    options = OptionParser.new do |opts|
      opts.version = VERSION
      opt(opts, sherlock, env) do |o|
        o.opt(:branch, "TRAVIS_BRANCH", "--branch STRING", "Branch being built")
        o.opt(:check, "--check", "validate that every file on the filesystem has a rule")
        o.opt(:component, "--component STRING", "name of component being built")
        o.opt(:pr, "TRAVIS_PULL_REQUEST", "--pr STRING", "pull request number or false")
        o.opt(:verbose, "-v", "--verbose", "--[no-]verbose", "Run verbosely")
      end
      opt(opts, files, env) do |o|
        o.opt(:range, "TRAVIS_COMMIT_RANGE", "--range SHA...SHA", "Git commit range")
      end
    end
    options.parse!(argv)
    argv.each { |file_name| require File.expand_path(file_name, Dir.pwd) }

    self
  end

  def opt(opts, model, env)
    yield OptSetter.new(opts, model, env)
  end

  def translator
    DslTranslator.new(self, sherlock, files, rules)
  end

  def run
    sherlock.run
  end

  def self.config
    yield instance.translator
  end

  def self.instance
    @instance ||= new
  end

  def self.run(argv, env)
    instance.parse(argv, env).run
  end
end

if __FILE__ == $PROGRAM_NAME
  $stdout.sync = true
  $stderr.sync = true

  JohnnyFive.run(ARGV, ENV)
end
