JohnnyFive.config do |matrix|
  # if this is a branch (not a PR) - then only run for master
  # comment out if you want to run for all branches
  matrix.branches << "master"

  # controllers: Gemfile, one
  # models: Gemfile, one
  matrix.suite %w(controllers models) do |cfg|
    cfg.file "Gemfile", :exact => true
    cfg.file "config", :ext => ""
    cfg.trigger "one"
  end

  # models: app/models/**/*.rb, test/fixtures
  matrix.suite "models" do |cfg|
    cfg.file "app/models", :ext => ".rb"
    cfg.file "db", :ext => ".rb"
    cfg.file "test/fixtures", :ext => ""
    cfg.test "test/models", :ext => "_test.rb"
  end

  matrix.suite "controllers" do |cfg|
    cfg.file "app/{controllers,views}", :ext => ".rb"
    cfg.file "app/views", :ext => ".jbuilder"
    cfg.file "app/helpers", :ext => ".rb"
    cfg.trigger "models"
    cfg.test "test/{controllers,views}", :ext => "_test.rb"
    cfg.test "test/helpers", :ext => "_test.rb"
  end

  matrix.suite "ui" do |cfg|
    cfg.file "app/assets", :ext => ""
    cfg.file "config", :ext => ""
    cfg.file "public", :ext => ""
    cfg.file "vendor", :ext => ""
    cfg.trigger "controller"
    cfg.test "test/integration", :ext => "_test.rb"
  end

  matrix.suite "j5" do |cfg|
    cfg.file "build_tools", :ext => ""
  end

  matrix.suite "one" do |cfg|
    cfg.file "gems/one", :except => %r{gems/one/test}, :ext => ""
    cfg.test "gems/one/test", :ext => ""
  end

  matrix.suite :none do |cfg|
    cfg.file "README.md", :exact => true
    cfg.file "Rakefile", :exact => true

    cfg.file "bin", :ext => ""
    cfg.file "log", :ext => ""
    cfg.file "lib/tasks", :ext => ""
    cfg.file "tmp", :ext => ""
  end

  matrix.suite :all do |cfg|
    cfg.test "test/test_helper.rb"
  end
end
