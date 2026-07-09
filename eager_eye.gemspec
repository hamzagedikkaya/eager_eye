# frozen_string_literal: true

require_relative "lib/eager_eye/version"

Gem::Specification.new do |spec|
  spec.name = "eager_eye"
  spec.version = EagerEye::VERSION
  spec.authors = ["hamzagedikkaya"]
  spec.email = ["gedikkayahamza@gmail.com"]

  spec.summary = "Static analysis tool for detecting N+1 queries in Rails applications"
  spec.description = "EagerEye detects N+1 query problems using AST analysis without running your code."
  spec.homepage = "https://github.com/hamzagedikkaya/eager_eye"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/hamzagedikkaya/eager_eye/blob/master/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile images/ examples/])
    end
  end
  # Guard against shipping a broken gem: if a lib/**/*.rb file exists on disk
  # but isn't in spec.files (e.g. `gem build` run before a new file was
  # committed, so `git ls-files` didn't see it), the published gem would raise
  # LoadError on `require "eager_eye"`. Fail the build loudly instead. This is
  # exactly the bug that shipped 1.3.2 without lib/eager_eye/source_parser.rb.
  untracked_lib = Dir.chdir(__dir__) { Dir["lib/**/*.rb"] } - spec.files
  unless untracked_lib.empty?
    raise "eager_eye.gemspec: these lib files are missing from the gem " \
          "(commit them before building): #{untracked_lib.join(", ")}"
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "ast", "~> 2.4"
  spec.add_dependency "parser", "~> 3.3"
end
