#!/usr/bin/env ruby

require 'forwardable'
require 'optionparser'

class JohnnyFive
  VERSION = "0.0.3"

  class OptSetter
    def initialize(opts, model)
      @opts  = opts
      @model = model
    end

    def opt(value, *args)
      unless args[0].start_with?("-") # support environment variable being specified
        env = args.shift
        ev = ENV[env]
        @model.send("#{value}=", ev) if ev
        args.last << " (#{env}=#{ev || "<not set>"})"
      end
      @opts.on(*args) { |v| @model.send("#{value}=", v) }
    end
  end

  def opt(opts, model)
    yield OptSetter.new(opts, model)
  end

  class Travis
    # @return <String> pull request number (e.g.: "555" or "false" for a branch)
    attr_accessor :pr
    # @return <String> branch being built (e.g.: master)
    attr_accessor :branch
    # @return <String> component being built
    attr_accessor :component
    # @return <Boolean> true to show verbose messages
    attr_accessor :verbose
    attr_accessor :commit_range

    def pr?
      @pr != "false"
    end

    # @return <String> commit range (e.g.: begin...end commit)
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

  class Sherlock
    extend Forwardable

    def initialize(travis)
      @travis = travis
      @shallow_rules = {}
      @shallow_dependencies = {}
      @branches = []
    end

    # Hash<String,Array<Regexp>> target and files that will trigger it
    attr_accessor :shallow_rules
    # Hash<String,Array<String>> target and targets that will trigger it
    attr_accessor :shallow_dependencies
    # Array<String> branches that will build (all others will be ignored)
    attr_accessor :branches

    def_delegators :@travis, :pr?, :branch, :component, :files, :verbose, :list
    def_delegators :@travis

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

    def triggered?(target)
      targets = dependencies([target, :all])
      regexps = rules(targets)
      regexp = Regexp.union(regexps)
      list("DETECT #{target}") { targets }
      list("REGEX:") { regexps } if verbose

      files.detect { |fn| regexp.match(fn) }.tap { |fn| puts "triggered by #{fn}" if verbose && fn }
    end

    # @return Array[String] files that are not covered by any rules (used by --check)
    def not_covered
      all_files = Regexp.union(shallow_rules.values.flatten)
      files.select { |fn| !all_files.match(fn) }
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
        (shallow_rules[target] ||= []) << regex(glob, options) # TODO: support options[:except]
      end
      self
    end

    alias_method :test, :file

    def trigger(src_target, targets = nil)
      src_target, targets = @suite, src_target if targets.nil?
      targets = [targets] unless targets.kind_of?(Array)
      targets.each do |target|
        (shallow_dependencies[target]||=[]) << src_target
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

    def regex(glob, options)
      # in the glob world, tack on '**/*#{options[:ext]}'
      ext = ".*#{options[:ext]}" if options[:ext]
      # would be nice to replace '{' with '(?' to not capture
      /#{glob.tr("{,}","(|)")}#{ext}/
    end
  end

  # @return <String|Nil> name of file to touch if no files have changed
  attr_accessor :touch
  # @return <Number|Nil> value of exit status if no files have changed
  attr_accessor :exit_value
  attr_accessor :check
  attr_reader :travis
  attr_accessor :sherlock

  def initialize
    @travis = Travis.new
    @sherlock = Sherlock.new(@travis)
  end

  def parse(argv, env)
    options = OptionParser.new do |opts|
      opts.version = VERSION
      opt(opts, travis) do |o|
        o.opt(:verbose, "-v", "--verbose", "--[no-]verbose", "Run verbosely")
        o.opt(:commit_range, "TRAVIS_COMMIT_RANGE", "--range SHA...SHA", "Git commit range")
        o.opt(:pr, "TRAVIS_PULL_REQUEST", "--pr STRING", "pull request number or false")
        o.opt(:branch, "TRAVIS_BRANCH", "--branch STRING", "Branch being built")
        o.opt(:component, "--component STRING", "name of component being built")
      end
      opt(opts, self) do |o|
        o.opt(:touch, "--touch STRING", "if the build has not changed, touch this file")
        o.opt(:exit_value, "--exit NUMBER", "if the build did not change, exit with this")
        o.opt(:check, "--check", "validate that there is a rule for all changed files")
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
