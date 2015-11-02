#!/usr/bin/env ruby

require 'forwardable'
require 'optionparser'

class JohnnyFive
  VERSION = "0.0.3"

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

  def opt(opts, model, env)
    yield OptSetter.new(opts, model, env)
  end

  # Travis environment and git configuration
  class Travis
    # @return [String] pull request number (e.g.: "555" or "false" for a branch)
    attr_accessor :pr
    # @return [String] branch being built (e.g.: master)
    attr_accessor :branch
    # @return [String] component being built
    attr_accessor :component
    # @return [Boolean] true to show verbose messages
    attr_accessor :verbose
    # @return [String] the commits that have changed for this build (e.g.: first_commit...last_commit)
    attr_accessor :commit_range

    def pr?
      @pr != "false"
    end

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

    def list(name, always_display = true)
      entries = yield
      if always_display || !entries.empty?
        puts "======="
        puts "#{name}"
        puts entries.map { |fn| " - #{fn}" }
        puts
      end
    end

    def files(ref = range)
      git("log --name-only --pretty=\"format:\" #{ref}").split("\n").uniq.sort
    end

    def commits(ref = range)
      git("log --oneline --decorate #{ref}").split("\n")
    end

    def inform
      return self unless verbose
      puts "#{pr? ? "PR" : "  "} BRANCH    : #{branch}"
      puts "COMMIT_RANGE : #{range}#{" (derived from '#{commit_range}')" if range != commit_range}"
      puts "COMPONENT    : #{component}"
      list("COMMITS") { commits }
      list("FILES") { files } if verbose
      self
    end

    private

    def git(args, default_value = "")
      ret = `git #{args} 2> /dev/null`.chomp
      $CHILD_STATUS.to_i == 0 ? ret : default_value
    end
  end

  # uses facts to deduce a plan
  class Sherlock
    extend Forwardable

    def initialize(travis)
      @travis = travis
      @shallow_rules = {}
      @shallow_dependencies = {}
      @branches = []
    end

    # @return [Hash<String,Array<Regexp>] target and the files that will trigger a build
    attr_accessor :shallow_rules
    # @return [Hash<String,Array<String>] target and targets that will trigger a build
    attr_accessor :shallow_dependencies
    # @return [Array<String>|Nil] For a non-PR, branches that will trigger a build (all others will be ignored)
    attr_accessor :branches

    def_delegators :@travis, :pr?, :branch, :component, :files, :verbose, :list

    # main logic to determine what to do
    def deduce
      if pr?
        if component.empty? || triggered?(component)
          [true, "building PR for #{component || "none specified"}"]
        else
          [false, "skipping PR for unchanged: #{component}"]
        end
      else
        if branch.empty? || branches.empty? || branches.include?(branch)
          [true, "building branch: #{branch || "none specified"}"]
        else
          [false, "skipping branch: #{branch} (not #{branches.join(", ")})"]
        end
      end
    end

    # @return [Boolean] true if the changed files trigger this target
    def triggered?(target, src_files = files)
      targets = dependencies([target, :all])
      regexps = rules(targets)
      regexp = Regexp.union(regexps)
      list("DETECT #{target}") { targets }
      list("REGEX:") { regexps } if verbose

      src_files.detect { |fn| regexp.match(fn) }.tap { |fn| puts "triggered by #{fn}" if verbose && fn }
    end

    # @return Array[String] files that are not covered by any rules (used by --check)
    def not_covered(src_files = files)
      all_files = Regexp.union(shallow_rules.values.flatten)
      src_files.select { |fn| !all_files.match(fn) }
    end

    # configuration dsl

    def suite(name)
      @suite = name
      yield self
    end

    def file(glob, targets = nil, options = {})
      targets, options = @suite, targets if targets.kind_of?(Hash)

      targets = [targets] unless targets.kind_of?(Array)
      targets.each do |target|
        (shallow_rules[target] ||= []) << regex(glob, options)
      end
      self
    end

    alias_method :test, :file

    def trigger(src_target, targets = nil)
      src_target, targets = @suite, src_target if targets.nil?
      targets = [targets] unless targets.kind_of?(Array)
      targets.each do |target|
        (shallow_dependencies[target] ||= []) << src_target
      end
      self
    end

    # private

    def trigger_regex(*targets)
      Regexp.union(rules(targets))
    end

    def rules(targets)
      targets.flat_map { |target| shallow_rules[target] }.uniq.compact
    end

    def dependencies(targets)
      count = 0
      # keep doing this until we stop adding some
      while(count != targets.size)
        count = targets.size
        targets += targets.flat_map { |target| shallow_dependencies[target] }
        targets.compact!
        targets.uniq!
      end
      targets.flatten! || targets
    end

    private

    # TODO: find a way to support options except
    def regex(glob, options)
      # in the glob world, tack on '**/*#{options[:ext]}'
      ext = ".*#{options[:ext]}" if options[:ext]
      # would be nice to replace '{' with '(?' to not capture
      /#{glob.tr("{,}","(|)")}#{ext}/
    end
  end

  # @return [String|Nil] name of file to touch if no files have changed
  attr_accessor :touch
  # @return [Number|Nil] value of exit status if no files have changed
  attr_accessor :exit_value
  # @return [Boolean] true if the changed files should be validated against rules
  attr_accessor :check
  attr_reader :travis, :sherlock

  def initialize
    @travis = Travis.new
    @sherlock = Sherlock.new(@travis)
  end

  def parse(argv, env)
    options = OptionParser.new do |opts|
      opts.version = VERSION
      opt(opts, travis, env) do |o|
        o.opt(:branch, "TRAVIS_BRANCH", "--branch STRING", "Branch being built")
        o.opt(:commit_range, "TRAVIS_COMMIT_RANGE", "--range SHA...SHA", "Git commit range")
        o.opt(:component, "--component STRING", "name of component being built")
        o.opt(:pr, "TRAVIS_PULL_REQUEST", "--pr STRING", "pull request number or false")
        o.opt(:verbose, "-v", "--verbose", "--[no-]verbose", "Run verbosely")
      end
      opt(opts, self, env) do |o|
        o.opt(:check, "--check", "validate that there is a rule for all changed files")
        o.opt(:exit_value, "--exit NUMBER", "if the build did not change, exit with this")
        o.opt(:touch, "--touch STRING", "if the build has not changed, touch this file")
      end
      opts.on("--config STRING", "Use configuration file") { |file_name| require File.expand_path(file_name, Dir.pwd) }
    end
    options.parse!(argv)

    self
  end

  def run
    travis.inform
    travis.list("UNCOVERED", false) { sherlock.not_covered } if check
    run_it, reason = sherlock.deduce
    skip!(reason) unless run_it
  end

  # logic
  def skip!(reason)
    $stderr.puts "==> #{reason} <=="
    File.write(touch, reason) if touch
    exit(self.exit_value.to_i) if exit_value
  end

  def self.instance
    @instance ||= new
  end

  def self.config
    yield instance.sherlock
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
