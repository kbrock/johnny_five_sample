JohnnyFive.config do |matrix|
  # if this is a branch (not a PR) - then only run for master
  # comment out if you want to run for all branches
  matrix.branches << "master"

  # controllers: Gemfile, one
  # models: Gemfile, one
  matrix.suite %w(controllers models) do |cfg|
    cfg.file "Gemfile"
    cfg.file "config/**/*"
    cfg.trigger "one"
  end

  # models: app/models/**/*.rb, test/fixtures
  matrix.suite "models" do |cfg|
    cfg.file "app/models/**/*"
    cfg.file "db/**/*.rb"
    cfg.file "test/fixtures/**/*"
    cfg.test "test/models/**/*_test.rb"
  end

  matrix.suite "controllers" do |cfg|
    cfg.file "app/controllers/**/*.rb"
    cfg.file "app/views/**/*"
    cfg.file "app/helpers/**/*"
    cfg.trigger "models"
    cfg.test "test/{controllers,views}/**/*_test.rb"
    cfg.test "test/helpers/**/*_test.rb"
  end

  matrix.suite "ui" do |cfg|
    cfg.file "app/assets/**/*"
    cfg.file "config/**/*"
    cfg.file "public/**/*"
    cfg.file "vendor/**/*"
    cfg.trigger "controller"
    cfg.test "test/integration/**/*_test.rb"
  end

  matrix.suite "j5" do |cfg|
    cfg.file "build_tools/**/*"
  end

  matrix.suite "one" do |cfg|
    # would like to say except test
    cfg.file "gems/one/**/*"
    cfg.test "gems/one/test/**/*"
  end

  matrix.suite :none do |cfg|
    cfg.file "README.md"
    cfg.file "Rakefile"

    cfg.file "bin/**/*"
    cfg.file "log/**/*"
    cfg.file "lib/tasks/**/*"
    cfg.file "tmp/**/*"
  end

  matrix.suite :all do |cfg|
    cfg.test "test/test_helper.rb"
  end
end
