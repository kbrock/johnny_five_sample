#!/usr/bin/env ruby

require "forwardable"

class JohnnyFive
  class Travis
    # @return <String> pull request number (e.g.: "555" or "false" for a branch)
    attr_accessor :pr
    # @return <String> branch being built (e.g.: master)
    attr_accessor :branch
    # @return <String> component being built
    attr_accessor :component
    # @return <String|Nil> suffix for test suite name (e.g.: -spec)
    attr_accessor :suffix
    # @return <Array<String>> list of variables that will hold the component name
    attr_accessor :component_name
    attr_accessor :verbose

    def initialize
      @component_name = []
    end

    def parse(_argv, env)
      @pr     = env['TRAVIS_PULL_REQUEST']
      @branch = env['TRAVIS_BRANCH']
      @commit_range = env['TRAVIS_COMMIT_RANGE'] || ""
      @component = component_name.detect { |name| env[name] } || ""
      self
    end

    def pr?
      @pr != "false"
    end

    def target
      "#{component}#{suffix}"
    end

    def range=(value)
      @commit_range = val
    end

    # @return <String> commit range (e.g.: begin...end commit)
    def range
      if commit_range == ""
        "FETCH_HEAD^...FETCH_HEAD" # HEAD
      elsif !commit_range.include?("...")
        "#{commit_range}^...#{commit_range}"
      else
        commit_range
      end
    end

    def list(name, entries = nil)
      puts "======="
      puts "#{name}"
      puts (entries || yield).map { |fn| " - #{fn}" }
      puts
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
      list("FILES") { files }
      self
    end

    private

    attr_reader :commit_range

    def git(args, default_value = "")
      ret = `git #{args} 2> /dev/null`.chomp
      $?.to_i == 0 ? ret : default_value
    end
  end

  class Sherlock
    extend Forwardable

    def initialize(travis)
      # Travis
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

    def_delegators :@travis, :pr, :pr?, :branch, :target, :files, :verbose, :list, :component_name
    def_delegators :@travis, :pr=, :branch=, :component=, :suffix=, :range=, :verbose=, :component_name=

    def deduce
      if pr?
        if triggered?(target)
          [true, "building PR, changed: #{target}"]
        else
          [false, "skipping PR, unchanged: #{target}"]
        end
      else
        if branches.empty? || branches.include?(branch)
          [true, "building branch: #{branch}"]
        else
          [false, "skipping branch: #{branch} (not #{@branch_force.join(", ")})"]
        end
      end
    end

    def triggered?(target)
      targets = dependencies([target, :all])
      regexps = rules(targets)
      regexp = Regexp.union(regexps)
      list "detect #{target}", targets
      list "rex:", regexps
      
      ret = files.detect { |fn| regexp.match(fn) }.tap { |fn| puts "triggered by #{fn}" if verbose && fn }
    end

    # @return Array[String] files that are not covered by shallow_rules
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
        (shallow_rules[target]||=[]) << regex(glob, options) # TODO: support options[:except]
      end
      self
    end

    alias test file

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

  attr_accessor :touch
  attr_reader :travis
  attr_accessor :sherlock

  def initialize
    @travis = Travis.new
    @sherlock = Sherlock.new(@travis)
  end

  def parse(argv, env)
    @touch = "#{env["TRAVIS_BUILD_DIR"]}/.skip-ci"
    travis.parse(argv, env).inform
    travis.list "UNCOVERED", sherlock.not_covered if travis.verbose
    self
  end

  def run
    run_it, reason = sherlock.deduce
    skip!(reason) unless run_it
  end

  # logic
  def skip!(reason)
    $stderr.puts "==> #{reason} <=="
    File.write(touch, reason) if touch
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

  JohnnyFive.config do |cfg|
    cfg.suffix = "-spec"
    cfg.component_name += %w(TEST_SUITE GEM)
    cfg.verbose = true
    # only build master branch (and PRs)
    cfg.branches << "master"
    cfg.file "Gemfile",                        %w(controllers models), :exact => true
    cfg.file "app/{assets,controllers,views}", "controllers", :ext => ".rb"
    cfg.file "app/models",                     "models", :ext => ".rb"
    cfg.file "app/helpers",                    "controllers", :ext => ".rb"
    cfg.file "bin",                            :none, :ext => ""
    cfg.file "build_tools",                    :none, :ext => ""
    # except not currently covered
    cfg.file "gems/one",                       "one", :except => %r{gems/one/test}, :ext => ""
    cfg.file "public",                         "ui", :ext => ""
    cfg.file "vendor",                         "ui", :ext => ""

    cfg.test "test/{controllers,views}",       "controllers-spec", :ext => "_spec.rb"
    cfg.test "test/fixtures",                  "models", :ext => ""
    cfg.test "test/helpers",                   "controllers-spec", :ext => "_spec.rb"
    cfg.test "test/integration",               "ui-spec", :ext => "_spec.rb"
    cfg.test "test/models",                    "models-spec", :ext => "_spec.rb"
    cfg.file "gems/one/test",                  "one-spec", :ext => ""
    cfg.test "test/test_helper.rb",            :all

    cfg.trigger "controllers",                 "ui"
    cfg.trigger "models",                      "controllers"
    cfg.trigger "one",                         %w(controllers models)

    cfg.trigger "controllers",                 "controllers-spec"
    cfg.trigger "models",                      "models-spec"
    cfg.trigger "one",                         "one-spec"
    cfg.trigger "ui",                          "ui-spec"
  end

  JohnnyFive.run(ARGV, ENV)
end
