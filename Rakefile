require 'rubygems'
require 'activerecord'
ActiveRecord::ActiveRecordError # hack for https://rails.lighthouseapp.com/projects/8994/tickets/2577-when-using-activerecordassociations-outside-of-rails-a-nameerror-is-thrown

$:.unshift File.join(File.expand_path(File.dirname(__FILE__)), '/../hobofields/lib')
$:.unshift File.join(File.expand_path(File.dirname(__FILE__)), '/../hobosupport/lib')
require 'hobosupport'
require 'hobofields'

namespace "test" do
  desc "Run the doctests"
  task :doctest do |t|
    exit(1) if !system("rubydoctest test/*.rdoctest")
  end

  desc "Run the unit tests"
  task :unit do |t|
    Dir["test/test_*.rb"].each do |f|
      exit(1) if !system("ruby #{f}")
    end
  end
end

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.version      = HoboFields::VERSION
    gemspec.name         = "hobofields"
    gemspec.email        = "tom@tomlocke.com"
    gemspec.summary      = "Rich field types and migration generator for Rails"
    gemspec.homepage     = "http://hobocentral.net/"
    gemspec.authors      = ["Tom Locke"]
    gemspec.rubyforge_project = "hobo"
    gemspec.add_dependency("rails", [">= 2.2.2"])
    gemspec.add_dependency("hobosupport", ["= #{HoboFields::VERSION}"])
  end
  Jeweler::GemcutterTasks.new
  Jeweler::RubyforgeTasks.new do |rubyforge|
    rubyforge.doc_task = false
  end
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
end
