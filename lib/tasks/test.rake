require 'rake/testtask'

Rake::TestTask.new("test:ui") do |t|
  t.libs << "test"
  t.pattern = "test/{helpers,integration}/*_test.rb"
end

Rake::TestTask.new("test:controllers") do |t|
  t.libs << "test"
  t.pattern = "test/controllers/*_test.rb"
end

Rake::TestTask.new("test:models") do |t|
  t.libs << "test"
  t.pattern = "test/models/**/*_test.rb"
end

Rake::TestTask.new("test:j5") do |t|
  t.libs << "build_tools"
  t.pattern = "build_tools/*_test.rb"
end

namespace :test do
  task :setup => %w(db:create db:migrate db:schema:dump db:test:prepare)

  namespace :ui do
    task :setup => "test:setup"
  end

  namespace :controllers do
    task :setup => "test:setup"
  end

  namespace :models do
    task :setup => "test:setup"
  end

  namespace :j5 do
    task :setup
  end
end
