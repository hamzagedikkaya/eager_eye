# frozen_string_literal: true

require_relative "lib/eager_eye/version"

Gem::Specification.new do |spec|
  spec.name = "eager_eye"
  spec.version = EagerEye::VERSION
  spec.authors = ["hamzagedikkaya"]
  spec.email = ["gedikkayahamza@gmail.com"]

  spec.summary = "A Ruby gem for detecting N+1 queries and eager loading issues in Rails applications"
  spec.description = "EagerEye helps you identify and fix N+1 query problems by analyzing your ActiveRecord queries and suggesting eager loading optimizations."
  spec.homepage = "https://github.com/hamzagedikkaya/eager_eye"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/hamzagedikkaya/eager_eye"
  spec.metadata["changelog_uri"] = "https://github.com/hamzagedikkaya/eager_eye/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
