#!/usr/bin/env ruby

require 'forwardable'
require 'optionparser'

class JohnnyFive
  VERSION = "0.0.5"

  class GitFileList
    def self.files(range)
      git("log --name-only --pretty=\"format:\" #{range}").split("\n").uniq.sort
    end

    def self.[](range)
      files(range)
    end

    def self.commits(range)
      git("log --oneline --decorate #{range}").split("\n")
    end

    def self.fix_range(range)
      range ||= "FETCH_HEAD"
      range.include?("...") ? range : "#{range}^...#{range}"
    end

    def self.git(args, default_value = "")
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

      Regexp.new(glob.gsub(%r{([{},.]|\*\*/\*|\*\*/|\*)}) do
        case $1
        when '**/*' then '.*'    # directory and file match
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
      while count != targets.size
        count = targets.size
        (targets += basic_dependencies[targets]).tap(&:compact!).tap(&:uniq!)
      end
      targets
    end

    # @return [Regexp] rule to match every file that is covered by a rule (for sanity checks)
    def every
      Regexp.union((basic_rules.values + shallow_rules.values).uniq)
    end
  end

  ########### FOLD ###########

  # Easy dsl to populate rules (or sherlock)
  class DslTranslator
    extend Forwardable
    def initialize(sherlock, rules = nil)
      @rules = rules || sherlock.rules
      @sherlock = sherlock
    end

    def suite(name)
      @suite = name
      yield self
    end

    def file(glob)
      basic_rules[@suite] = Rules.glob2regex(glob)
    end

    def test(glob)
      shallow_rules[@suite] = Rules.glob2regex(glob)
    end

    def trigger(target)
      basic_dependencies[@suite] = target
    end

    def_delegators :@sherlock, :branch=, :branches, :branches=, :check=, :component=, :verbose=, :range= ,:pr=
    def_delegators :@rules, :basic_dependencies, :basic_rules, :shallow_rules
  end

  # uses facts to deduce a plan
  class Sherlock
    extend Forwardable

    def initialize(rules)
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
    # @return [String] git commit range (e.g.: FETCH_HEAD^...FETCH_HEAD)
    attr_accessor :range

    attr_accessor :rules

    def range=(range)
      @range = ::JohnnyFive::GitFileList.fix_range(range)
    end

    def pr?
      pr != false && pr != "false"
    end

    def branch_match?
      branch.nil? || branch.empty? || branches.empty? || branches.include?(branch)
    end

    # @return [Boolean] true if the changed files trigger this target
    def triggered?(target)
      return true if component.nil? || component.empty?
      regexp = Regexp.union(rules[target])
      GitFileList[range].detect { |fn| regexp.match(fn) }
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

    def run
      run_it, reason = deduce
      puts "==> #{reason} <=="
      exit(1) unless run_it
    end
  end

  ###### Logic and DSL above ######

  # Class to parse ENV and ARGV
  # see also parse method
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
        # add env value onto opts help message
        args.last << " (#{env}=#{ev || "<not set>"})"
      end
      @opts.on(*args) { |v| @model.send("#{value}=", v) }
    end
  end

  attr_reader :sherlock, :rules

  def initialize
    @rules = RuleList.new
    @sherlock = Sherlock.new(@rules)
  end

  def opt(opts, model, env)
    yield OptSetter.new(opts, model, env)
  end

  def parse(argv, env)
    options = OptionParser.new do |opts|
      opts.version = VERSION
      opt(opts, sherlock, env) do |o|
        o.opt(:branch, "TRAVIS_BRANCH", "--branch STRING", "Branch being built")
        o.opt(:check, "CHECK", "--check", "validate that every file on the filesystem has a rule")
        o.opt(:component, "COMPONENT", "--component STRING", "name of component being built")
        o.opt(:pr, "TRAVIS_PULL_REQUEST", "--pr STRING", "pull request number or false")
        o.opt(:range, "TRAVIS_COMMIT_RANGE", "--range SHA...SHA", "Git commit range")
        o.opt(:verbose, "VERBOSE", "-v", "--verbose", "--[no-]verbose", "Run verbosely")
      end
    end
    options.parse!(argv)
    argv.each { |file_name| require File.expand_path(file_name, Dir.pwd) }

    self
  end

  def config
    DslTranslator.new(sherlock, rules)
  end

  def self.config
    yield instance.config
  end

  def self.instance
    @instance ||= new
  end

  def inform
    puts "#{sherlock.pr? ? "PR" : "  "} BRANCH    : #{sherlock.branch}"
    puts "COMPONENT    : #{sherlock.component}"
    puts "COMMIT_RANGE : #{sherlock.range}"
    list("COMMITS") { GitFileList.commits(sherlock.range) }
    list("FILES") { GitFileList.files(sherlock.range) } if sherlock.verbose
    list("DETECT:") { rules.dependencies(sherlock.component) } if sherlock.verbose
    list("REGEX:") { rules[sherlock.component] } if sherlock.verbose || sherlock.check
    self
  end

  def run
    inform
    sanity_check if sherlock.check
    sherlock.run
  end

  def self.run(argv, env)
    instance.run(argv, env)
  end

  private

  def sanity_check
    all_files = every_file
    all_rules = rules.every
    list("UNCOVERED:", false) { all_files.select { |fn| !all_rules.match(fn) } }
  end

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

if __FILE__ == $PROGRAM_NAME
  $stdout.sync = true
  $stderr.sync = true

  JohnnyFive.parse(ARGV, ENV).run
end
