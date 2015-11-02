  JohnnyFive.config do |cfg|
    # if this is a branch (not a PR) - then only run for master
    # comment out if you want to run for all branches
    cfg.branches << "master"

    # if the Gemfile (exact name) changes, then the controllers and models (and dependencies) need to run
    cfg.file "Gemfile",                        %w(controllers models), :exact => true
    cfg.file "README.md",                      :none, :exact => true
    cfg.file "Rakefile",                       :none, :exact => true
    cfg.file "app/assets",                     "ui", :ext => ""
    # if any ruby files in these directories/descendents change, then trigger the controller specs/dependencies
    cfg.file "app/{controllers,views}",        "controllers", :ext => ".rb"
    cfg.file "app/{views}",                    "controllers", :ext => ".jbuilder"
    cfg.file "app/models",                     "models", :ext => ".rb"
    cfg.file "app/helpers",                    "controllers", :ext => ".rb"
    # ignore anything in bin directory. explicitly state, we know about this file, just ignore it
    cfg.file "bin",                            :none, :ext => ""
    cfg.file "build_tools",                    :none, :ext => ""
    cfg.file "config",                         %w(controllers models ui), :ext => ""
    cfg.file "db",                             "models", :ext => ".rb"
    # TODO: except not currently supported
    cfg.file "gems/one",                       "one", :except => %r{gems/one/test}, :ext => ""
    cfg.file "public",                         "ui", :ext => ""
    cfg.file "tmp",                            :none, :ext => ""
    cfg.file "log",                            :none, :ext => ""
    cfg.file "lib/tasks",                      :none, :ext => ""
    cfg.file "vendor",                         "ui", :ext => ""

    # the tests have changed, run the corresponding tests (but not necessarily the dendencies)
    cfg.test "test/{controllers,views}",       "controllers", :ext => "_test.rb"
    cfg.file "test/fixtures",                  "models", :ext => ""
    cfg.test "test/helpers",                   "controllers", :ext => "_test.rb"
    cfg.test "test/integration",               "ui", :ext => "_test.rb"
    cfg.test "test/models",                    "models", :ext => "_test.rb"
    cfg.test "gems/one/test",                  "one", :ext => ""
    cfg.test "test/test_helper.rb",            %w(models controllers)

    # if the code changes, then run the dependendencies as well.
    cfg.trigger "controllers",                 "ui"
    cfg.trigger "models",                      "controllers"
    cfg.trigger "one",                         %w(controllers models)
  end
