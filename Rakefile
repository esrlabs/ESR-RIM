$:.unshift(File.dirname(__FILE__)+"/lib")

require 'rubygems/package_task'
require 'rdoc/task'
require 'rim/version'

DocFiles = [
  "README.md", "CHANGELOG"
  ]

RTextGemSpec = Gem::Specification.new do |s|
  s.name = "esr-rim"
  s.version = RIM::Version::Version
  s.date = Time.now.strftime("%Y-%m-%d")
  s.summary = "RIM - multi git tool"
  s.description = "RIM lets you work with multiple git repositories from within one single git repository."
  s.authors = "ESR Labs GmbH"
  s.homepage = "http://github.com/esrlabs/esr-rim"
  s.add_dependency('subcommand', '>= 1.0.6')
  gemfiles = Rake::FileList.new
  gemfiles.include("{lib,test}/**/*")
  gemfiles.include(DocFiles)
  gemfiles.include("Rakefile")
  s.files = gemfiles
  s.rdoc_options = ["--main", "README.md", "-x", "test"]
  s.extra_rdoc_files = DocFiles
  s.bindir = "bin"
  s.executables = ["rim"]
end

RDoc::Task.new do |rd|
  rd.main = "README.md"
  rd.rdoc_files.include(DocFiles)
  rd.rdoc_files.include("lib/**/*.rb")
  rd.rdoc_dir = "doc"
end

RTextPackageTask = Gem::PackageTask.new(RTextGemSpec) do |p|
  p.need_zip = false
end

task :prepare_package_rdoc => :rdoc do
  RTextPackageTask.package_files.include("doc/**/*")
end

desc 'run unit tests'
task :unit_tests do
  sh "ruby test/unit_tests.rb"
end

desc 'run integration tests'
task :int_tests do
  sh "RIM=\"ruby #{Dir.pwd}/rim.rb\" cram integration_tests/*.t"
end

task :release => [:prepare_package_rdoc, :package]

task :clobber => [:clobber_rdoc, :clobber_package]

task :default => :run_tests
