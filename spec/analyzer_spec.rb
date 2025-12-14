# frozen_string_literal: true

RSpec.describe EagerEye::Analyzer do
  let(:fixtures_path) { File.expand_path("fixtures", __dir__) }

  before { EagerEye.reset_configuration! }

  describe "#initialize" do
    it "uses provided paths" do
      analyzer = described_class.new(paths: ["app/models"])
      expect(analyzer.paths).to eq(["app/models"])
    end

    it "uses configuration app_path when no paths provided" do
      EagerEye.configure { |c| c.app_path = "src" }
      analyzer = described_class.new
      expect(analyzer.paths).to eq(["src"])
    end

    it "converts single path to array" do
      analyzer = described_class.new(paths: "app")
      expect(analyzer.paths).to eq(["app"])
    end
  end

  describe "#run" do
    context "with fixture files" do
      it "detects issues in sample_controller.rb" do
        analyzer = described_class.new(paths: File.join(fixtures_path, "sample_controller.rb"))
        issues = analyzer.run

        expect(issues).not_to be_empty
        expect(issues.map(&:detector)).to include(:loop_association)
      end

      it "detects issues in sample_serializer.rb" do
        analyzer = described_class.new(paths: File.join(fixtures_path, "sample_serializer.rb"))
        issues = analyzer.run

        expect(issues).not_to be_empty
        expect(issues.map(&:detector)).to include(:serializer_nesting)
      end

      it "finds no issues in clean_code.rb" do
        analyzer = described_class.new(paths: File.join(fixtures_path, "clean_code.rb"))
        issues = analyzer.run

        expect(issues).to be_empty
      end

      it "analyzes entire directory" do
        analyzer = described_class.new(paths: fixtures_path)
        issues = analyzer.run

        expect(issues.size).to be >= 2
      end
    end

    context "with excluded paths" do
      it "excludes files matching pattern" do
        EagerEye.configure do |config|
          config.excluded_paths = ["**/sample_controller.rb"]
        end

        analyzer = described_class.new(paths: fixtures_path)
        issues = analyzer.run

        controller_issues = issues.select { |i| i.file_path.include?("sample_controller") }
        expect(controller_issues).to be_empty
      end
    end

    context "with enabled_detectors configuration" do
      it "only runs enabled detectors" do
        EagerEye.configure do |config|
          config.enabled_detectors = [:serializer_nesting]
        end

        analyzer = described_class.new(paths: fixtures_path)
        issues = analyzer.run

        detectors = issues.map(&:detector).uniq
        expect(detectors).to eq([:serializer_nesting])
      end
    end

    context "with non-existent path" do
      it "returns empty array for non-existent file" do
        analyzer = described_class.new(paths: "/non/existent/path.rb")
        issues = analyzer.run

        expect(issues).to be_empty
      end
    end

    context "with invalid Ruby syntax" do
      it "skips files with syntax errors" do
        # Create a temp file with invalid syntax
        invalid_file = File.join(fixtures_path, "invalid_syntax.rb")
        File.write(invalid_file, "def foo(")

        begin
          analyzer = described_class.new(paths: invalid_file)
          issues = analyzer.run

          expect(issues).to be_empty
        ensure
          FileUtils.rm_f(invalid_file)
        end
      end
    end

    context "with glob patterns" do
      it "supports glob patterns in paths" do
        analyzer = described_class.new(paths: File.join(fixtures_path, "*.rb"))
        issues = analyzer.run

        expect(issues).not_to be_empty
      end
    end
  end

  describe "#issues" do
    it "returns accumulated issues after run" do
      analyzer = described_class.new(paths: fixtures_path)
      analyzer.run

      expect(analyzer.issues).to be_an(Array)
      expect(analyzer.issues.first).to be_a(EagerEye::Issue)
    end

    it "clears issues on subsequent runs" do
      analyzer = described_class.new(paths: fixtures_path)

      first_run_count = analyzer.run.size
      second_run_count = analyzer.run.size

      expect(first_run_count).to eq(second_run_count)
    end
  end
end
