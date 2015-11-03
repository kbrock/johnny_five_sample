#!/usr/bin/env ruby

require 'forwardable'
require 'optionparser'

class JohnnyFive
  VERSION = "0.0.4"

  class GitFileList
    include Enumerable
    # @return [String] the commits that have changed for this build (e.g.: first_commit...last_commit)
    attr_accessor :commit_range

    # @return [String] commit range (e.g.: begin...end commit)
    def range
      if commit_range == "" || commit_range.nil?
        "FETCH_HEAD^...FETCH_HEAD" # HEAD
      elsif !commit_range.include?("...")
        "#{commit_range}^...#{commit_range}"
      else
        commit_range
      end
    end

    def each(&block)
      all.each(&block)
    end

    def all
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

  class RuleList
    def initialize
      @shallow_rules        = Hash.new { |hash, key| hash[key] = [] }
      @non_dependent_rules  = Hash.new { |hash, key| hash[key] = [] }
      @shallow_dependencies = Hash.new { |hash, key| hash[key] = [] }
    end

    # @return [Hash<String,Array<Regexp>] target and the files that will trigger a build (but not dependent rules)
    attr_accessor :non_dependent_rules
    # @return [Hash<String,Array<Regexp>] target and the files that will trigger a build
    attr_accessor :shallow_rules
    # @return [Hash<String,Array<String>] target and targets that will trigger a build
    attr_accessor :shallow_dependencies

    # @param targets [Array<String>] list of targets. (please expand with `dependencies` first)
    # @return [Array<Regexp>] rules for all these targets
    def rules(targets)
      targets.flat_map { |target| shallow_rules[target] }.uniq.compact
    end

    # @param targets [Array<String>]
    # @return targets [Array<String>] list of all targets and dependent targets
    def dependencies(targets)
      main_target = targets.detect { |target| target != :all }
      count = 0
      # keep doing this until we stop adding some
      while count != targets.size
        count = targets.size
        targets += targets.flat_map { |target| shallow_dependencies[target] }
        targets.compact!
        targets.uniq!
      end
      # all the rules that target only this build
      targets += non_dependent_rules[main_target]
      targets.flatten! || targets
    end

    # verbose / debugging version of regexp / []
    def resolve(target)
      targets = dependencies([target, :all])
      regexps = rules(targets)
      [targets, regexps, Regexp.union(regexps)]
    end

    # @return [Regexp] rule to match this target
    def regexp(target)
      resolve(target).last
    end
    alias_method :[], :regexp

    # @return [Regexp] rule to match every file (for sanity checks)
    def all
      Regexp.union((shallow_rules.values.flatten + non_dependent_rules.values.flatten).uniq)
    end
  end

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
      targets, regexps, regexp = @rules.resolve(target)
      list("DETECT:") { targets } if verbose
      list("REGEX:") { regexps } if verbose || check
      files.all.detect { |fn| regexp.match(fn) }.tap { |fn| puts "build triggered by change to file #{fn}" if fn }
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
      puts "COMMIT_RANGE : #{files.range}#{" (derived from '#{files.commit_range}')" if files.range != files.commit_range}"
      list("COMMITS") { files.commits }
      list("FILES") { files } if verbose
      self
    end

    def sanity_check
      all_files = every_file
      all_rules = rules.all
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
    def_delegators :rules, :non_dependent_rules, :shallow_rules, :shallow_dependencies
    def_delegators :files, :commit_range=

    def suite(name)
      @suite = name
      yield self
    end

    # add a file that triggers this rule and all dependencies
    def file(glob, targets = nil, options = {}, rules = shallow_rules)
      targets, options = @suite, targets if targets.kind_of?(Hash)

      targets = [targets] unless targets.kind_of?(Array)
      targets.each do |target|
        (rules[target] ||= []) << regex(glob, options)
      end
      self
    end

    # add a file that triggers this rule (but not dependencies)
    def test(glob, targets = nil, options = {})
      file(glob, targets, options, non_dependent_rules)
    end

    # add a dependency between 2 rules
    def trigger(src_target, targets = nil)
      src_target, targets = @suite, src_target if targets.nil?
      targets = [targets] unless targets.kind_of?(Array)
      targets.each do |target|
        (shallow_dependencies[target] ||= []) << src_target
      end
      self
    end

    private

    def regex(glob, options)
      # in the glob world, tack on '**/*#{options[:ext]}'
      ext = ".*#{options[:ext]}" if options[:ext]
      # would be nice to replace '{' with '(?' to not capture
      /#{glob.tr("{,}", "(|)")}#{ext}/
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
        o.opt(:commit_range, "TRAVIS_COMMIT_RANGE", "--range SHA...SHA", "Git commit range")
      end
      opts.on("--config STRING", "Use configuration file") { |file_name| require File.expand_path(file_name, Dir.pwd) }
    end
    options.parse!(argv)

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
