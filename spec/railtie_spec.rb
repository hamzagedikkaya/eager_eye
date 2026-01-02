# frozen_string_literal: true

RSpec.describe "Railtie" do
  describe "config file loading" do
    let(:config_content) do
      <<~YAML
        excluded_paths:
          - app/legacy/**
        enabled_detectors:
          - loop_association
        app_path: src
        fail_on_issues: false
      YAML
    end

    it "parses YAML configuration correctly" do
      require "yaml"
      config = YAML.safe_load(config_content, symbolize_names: true)

      expect(config[:excluded_paths]).to eq(["app/legacy/**"])
      expect(config[:enabled_detectors]).to eq(["loop_association"])
      expect(config[:app_path]).to eq("src")
      expect(config[:fail_on_issues]).to be(false)
    end
  end

  describe "generator" do
    it "generator file exists" do
      generator_path = File.expand_path("../lib/eager_eye/generators/install_generator.rb", __dir__)
      expect(File.exist?(generator_path)).to be(true)
    end
  end
end
