JohnnyFive.config do |matrix|
  # if this is a branch (not a PR) - then only run for master
  # comment out if you want to run for all branches
  matrix.branches << "master"

  # controllers: Gemfile, one
  # models: Gemfile, one
  matrix.suite %w(controllers models) do |cfg|
    cfg.file "Gemfile", :exact => true
    cfg.trigger "one"
  end

  # models: app/models/**/*.rb, test/fixtures
  matrix.suite "models" do |cfg|
    cfg.file "app/models", :ext => ".rb"
    cfg.test "test/fixtures", :ext => ""
  end

  # models-spec: test/models/**/*_spec.rb, models
  matrix.suite "models-spec" do |cfg|
    cfg.test "test/models", :ext => "_spec.rb"
    cfg.trigger "models"
  end

  matrix.suite "controllers" do |cfg|
    cfg.file "app/{assets,controllers,views}", :ext => ".rb"
    cfg.file "app/helpers", :ext => ".rb"
    cfg.trigger "models"
  end

  matrix.suite "controllers-spec" do |cfg|
    cfg.test "test/{controllers,views}", :ext => "_spec.rb"
    cfg.test "test/helpers", :ext => "_spec.rb"
    cfg.trigger "controllers"
  end

  matrix.suite "ui" do |cfg|
    cfg.file "public", :ext => ""
    cfg.file "vendor", :ext => ""
    cfg.trigger "controller"
  end

  matrix.suite "ui-spec" do |cfg|
    cfg.test "test/integration", :ext => "_spec.rb"
    cfg.trigger "ui"
  end

  matrix.suite "one" do |cfg|
    cfg.file "gems/one", :except => %r{gems/one/test}, :ext => ""
  end

  matrix.suite "one-spec" do |cfg|
    cfg.file "gems/one/test", :ext => ""
    cfg.trigger "one"
  end

  matrix.suite :none do |cfg|
    cfg.file "bin", :ext => ""
    cfg.file "build_tools", :ext => ""
  end

  matrix.suite :all do |cfg|
    cfg.test "test/test_helper.rb"
  end
end