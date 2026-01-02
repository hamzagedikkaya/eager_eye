# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_group "Detectors", "lib/eager_eye/detectors"
  add_group "Reporters", "lib/eager_eye/reporters"
  minimum_coverage 90
end

require "eager_eye"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
