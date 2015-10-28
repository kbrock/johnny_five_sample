require 'rake/testtask'

Rake::TestTask.new("test:ui") do |t|
  t.libs << "test"
  t.pattern = "test/{controllers,helpers,integration}/*_test.rb"
end

Rake::TestTask.new("test:models") do |t|
  t.libs << "test"
  t.pattern = "test/models/**/*_test.rb"
end
