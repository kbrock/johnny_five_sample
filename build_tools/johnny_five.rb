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

    def parse(_argv, env)
      @pr     = env['TRAVIS_PULL_REQUEST']
      @branch = env['TRAVIS_BRANCH']
      @commit_range = env['TRAVIS_COMMIT_RANGE'] || ""
      @component = env['TEST_SUITE'] || env['GEM'] || ""
      @suffix = "-spec"
      self
    end

    def pr?
      @pr != "false"
    end

    def target
      "#{component}#{suffix}"
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

    def files(ref = range)
      git("log --name-only --pretty=\"format:\" #{ref}").split("\n").uniq.sort
    end

    def commits(ref = range)
      git("log --oneline --decorate #{ref}").split("\n")
    end

    def inform
      puts "#{pr? ? "PR" : "  "} BRANCH    : #{branch}"
      puts "COMMIT_RANGE : #{range}#{" (derived from '#{commit_range}')" if range != commit_range}"
      puts "component    : #{component}"
      puts "commits", commits
      puts "files", files
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
      @rules = {}
      @dependencies = {}
    end

    # Hash<String,Array<Regexp>> target and files that will trigger it
    attr_accessor :rules
    # Hash<String,Array<String>> target and targets that will trigger it
    attr_accessor :dependencies

    def_delegators :@travis, :pr, :pr?, :branch, :target, :files

    def deduce
      if pr?
        if triggered?(target)
          [true, "building PR, changed: #{target}"]
        else
          [false, "skipping PR, unchanged: #{target}"]
        end
      else
        if branch == "master"
          [true, "building branch: #{branch}"]
        else
          [false, "skipping branch: #{branch} (not master)"]
        end
      end
    end

    def all_deps(targets)
      targets = [targets] unless targets.kind_of?(Array)
      # require "byebug"
      # byebug
      count = 0
      while(count != targets.size)
        count = targets.size
        targets += targets.flat_map { |target| dependencies[target] }
        targets.compact!
        targets.uniq!
      end
      targets
    end

    def triggered?(target)
      targets = all_deps(target)
      regexps = targets.flat_map { |target| rules[target] }.uniq.compact

      regexp = Regexp.union(regexps)

      puts "detect #{target} --> #{targets.join(", ")}"
      puts "rex:", regexps.map(&:to_s)
      
      files.detect { |fn| regexp.match(fn) }.tap { |fn| puts "triggered by #{fn}" }
    end

    # dsl
    def suite(name)
      @suite = name
      yield self
    end

    def file(glob, targets = nil, options = {})
      targets, options = @suite, targets if targets.kind_of?(Hash)

      targets = [targets] unless targets.kind_of?(Array)
      targets.each do |target|
        (rules[target]||=[]) << regex(glob, options) # TODO: support options[:except]
      end
      self
    end

    alias test file

    def trigger(src_target, targets = nil)
      src_target, targets = @suite, src_target if targets.nil?
      targets = [targets] unless targets.kind_of?(Array)
      targets.each do |target|
        (dependencies[target]||=[]) << src_target
      end
      self
    end

    private

    def regex(glob, options)
      ext = ".*#{options[:ext]}" if options[:ext]
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
    cfg.file "Gemfile",                        %w(controllers models), :exact => true
    cfg.file "app/{assets,controllers,views}", "controllers", :ext => ".rb"
    cfg.file "app/models",                     "models", :ext => ".rb"
    cfg.file "app/helpers",                    "controllers", :ext => ".rb"
    cfg.file "bin",                            :none, :ext => ""
    cfg.file "build_tools",                    :all # temporary, switch to :none when done
    cfg.file "gems/one",                       "one", :except => %{gems/one/test}, :ext => ""
    cfg.file "public",                         "ui", :ext => ""
    cfg.file "vendor",                         "ui", :ext => ""

    cfg.test "test/{controllers,views}",       "controllers-spec", :ext => "_spec.rb"
    cfg.test "test/fixtures",                  "models", :ext => ""
    cfg.test "test/helpers",                   "controllers-spec", :ext => "_spec.rb"
    cfg.test "test/integration",               "ui-spec", :ext => "_spec.rb"
    cfg.test "test/models",                    "models-spec", :ext => "_spec.rb"
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
