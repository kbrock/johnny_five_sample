  JohnnyFive.config do |cfg|
    # if this is a branch (not a PR) - then only run for master
    # comment out if you want to run for all branches
    cfg.branches << "master"

    # if the Gemfile (exact name) changes, then the controllers and models (and dependencies) need to run
    cfg.file "Gemfile",                        %w(controllers models), :exact => true
    # if any ruby files in these 3 directories (and descendents) change, then controllers need to run
    cfg.file "app/{assets,controllers,views}", "controllers", :ext => ".rb"
    cfg.file "app/models",                     "models", :ext => ".rb"
    cfg.file "app/helpers",                    "controllers", :ext => ".rb"
    # ignore anything in bin directory. explicitly state, we know about this file, just ignore it
    cfg.file "bin",                            :none, :ext => ""
    cfg.file "build_tools",                    :none, :ext => ""
    # TODO: except not currently supported
    cfg.file "gems/one",                       "one", :except => %r{gems/one/test}, :ext => ""
    cfg.file "public",                         "ui", :ext => ""
    cfg.file "vendor",                         "ui", :ext => ""

    # the tests have changed, run the corresponding tests (but not necessarily the dendencies)
    cfg.test "test/{controllers,views}",       "controllers-spec", :ext => "_spec.rb"
    cfg.test "test/fixtures",                  "models", :ext => ""
    cfg.test "test/helpers",                   "controllers-spec", :ext => "_spec.rb"
    cfg.test "test/integration",               "ui-spec", :ext => "_spec.rb"
    cfg.test "test/models",                    "models-spec", :ext => "_spec.rb"
    cfg.file "gems/one/test",                  "one-spec", :ext => ""
    cfg.test "test/test_helper.rb",            :all

    # if the code changes, then run the dependendencies as well.
    cfg.trigger "controllers",                 "ui"
    cfg.trigger "models",                      "controllers"
    cfg.trigger "one",                         %w(controllers models)

    # if the code changes, then run the corresponding specs
    cfg.trigger "controllers",                 "controllers-spec"
    cfg.trigger "models",                      "models-spec"
    cfg.trigger "one",                         "one-spec"
    cfg.trigger "ui",                          "ui-spec"
  end
