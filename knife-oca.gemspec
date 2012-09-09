# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "knife-oca/version"

Gem::Specification.new do |s|
  s.name = "knife-oca"
  s.version = Knife::OCA::VERSION
  s.has_rdoc = true
  s.authors = ["Dennis Klein"]
  s.email = ["d.klein@gsi.de"]
  s.homepage = "http://www.github.com/Reverand221/knife-oca"
  s.summary = "OCA Support for Chef's Knife Command"
  s.description = s.summary
  s.extra_rdoc_files = ["README.rdoc", "LICENSE"]

  s.files = `git ls-files`.split("\n")
#  s.test_files = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.add_dependency "fog", "~> 1.3"
  s.add_dependency "chef", ">= 0.10.10"
#  %w(rspec-core rspec-expectations rspec-mocks rspec_junit_formatter).each { |gem| s.add_development_dependency gem }

  s.require_paths = ["lib"]
end
