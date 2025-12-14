# frozen_string_literal: true

RSpec.describe EagerEye::Configuration do
  subject(:config) { described_class.new }

  describe "#initialize" do
    it "sets default excluded_paths to empty array" do
      expect(config.excluded_paths).to eq([])
    end

    it "sets default enabled_detectors" do
      expect(config.enabled_detectors).to eq(%i[loop_association serializer_nesting missing_counter_cache])
    end

    it "sets default app_path to 'app'" do
      expect(config.app_path).to eq("app")
    end

    it "sets default fail_on_issues to true" do
      expect(config.fail_on_issues).to be(true)
    end
  end

  describe "attribute accessors" do
    it "allows setting excluded_paths" do
      config.excluded_paths = ["app/legacy/**"]
      expect(config.excluded_paths).to eq(["app/legacy/**"])
    end

    it "allows setting enabled_detectors" do
      config.enabled_detectors = [:loop_association]
      expect(config.enabled_detectors).to eq([:loop_association])
    end

    it "allows setting app_path" do
      config.app_path = "src"
      expect(config.app_path).to eq("src")
    end

    it "allows setting fail_on_issues" do
      config.fail_on_issues = false
      expect(config.fail_on_issues).to be(false)
    end
  end
end

RSpec.describe EagerEye do
  after { described_class.reset_configuration! }

  describe ".configuration" do
    it "returns a Configuration instance" do
      expect(described_class.configuration).to be_a(EagerEye::Configuration)
    end

    it "memoizes the configuration" do
      expect(described_class.configuration).to be(described_class.configuration)
    end
  end

  describe ".configure" do
    it "yields the configuration" do
      described_class.configure do |config|
        config.excluded_paths = ["test/**"]
        config.fail_on_issues = false
      end

      expect(described_class.configuration.excluded_paths).to eq(["test/**"])
      expect(described_class.configuration.fail_on_issues).to be(false)
    end
  end

  describe ".reset_configuration!" do
    it "resets configuration to defaults" do
      described_class.configure do |config|
        config.excluded_paths = ["something/**"]
      end

      described_class.reset_configuration!

      expect(described_class.configuration.excluded_paths).to eq([])
    end
  end
end
