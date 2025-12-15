# frozen_string_literal: true

require "eager_eye"
require "eager_eye/rspec/matchers"

RSpec.configure do |config|
  config.include EagerEye::RSpec::Matchers
end
