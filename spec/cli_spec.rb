# frozen_string_literal: true

RSpec.describe EagerEye::CLI do
  let(:fixtures_path) { File.expand_path("fixtures", __dir__) }

  before { EagerEye.reset_configuration! }

  describe "#run" do
    context "with --version" do
      it "prints version and exits with 0" do
        cli = described_class.new(["--version"])

        expect { cli.run }.to output(/EagerEye #{EagerEye::VERSION}/).to_stdout
        expect(cli.run).to eq(0)
      end
    end

    context "with --help" do
      it "prints help and exits with 0" do
        cli = described_class.new(["--help"])

        expect { cli.run }.to output(/Usage: eager_eye/).to_stdout
        expect(cli.run).to eq(0)
      end
    end

    context "with paths" do
      it "analyzes specified paths" do
        cli = described_class.new([fixtures_path, "--no-color"])

        expect { cli.run }.to output(/EagerEye Analysis Results/).to_stdout
      end

      it "returns 1 when issues found" do
        cli = described_class.new([File.join(fixtures_path, "sample_controller.rb"), "--no-color"])

        expect(cli.run).to eq(1)
      end

      it "returns 0 when no issues found" do
        cli = described_class.new([File.join(fixtures_path, "clean_code.rb"), "--no-color"])

        expect(cli.run).to eq(0)
      end
    end

    context "with --no-fail" do
      it "returns 0 even when issues found" do
        cli = described_class.new([File.join(fixtures_path, "sample_controller.rb"), "--no-fail", "--no-color"])

        expect(cli.run).to eq(0)
      end
    end

    context "with --format json" do
      it "outputs JSON format" do
        cli = described_class.new([fixtures_path, "--format", "json"])
        output = capture_stdout { cli.run }

        expect { JSON.parse(output) }.not_to raise_error
        expect(output).to include('"summary"')
        expect(output).to include('"issues"')
      end
    end

    context "with --exclude" do
      it "excludes matching files" do
        cli = described_class.new([
          fixtures_path,
          "--exclude", "**/sample_controller.rb",
          "--format", "json"
        ])

        output = capture_stdout { cli.run }
        result = JSON.parse(output)

        file_paths = result["issues"].map { |i| i["file_path"] }
        expect(file_paths).not_to include(a_string_matching(/sample_controller/))
      end
    end

    context "with --only" do
      it "runs only specified detectors" do
        cli = described_class.new([
          fixtures_path,
          "--only", "serializer_nesting",
          "--format", "json"
        ])

        output = capture_stdout { cli.run }
        result = JSON.parse(output)

        detectors = result["issues"].map { |i| i["detector"] }.uniq
        expect(detectors).to eq(["serializer_nesting"])
      end

      it "supports multiple detectors in --only" do
        cli = described_class.new([
          fixtures_path,
          "--only", "loop_association,missing_counter_cache",
          "--format", "json"
        ])

        output = capture_stdout { cli.run }
        result = JSON.parse(output)

        detectors = result["issues"].map { |i| i["detector"] }.uniq
        expect(detectors).to match_array(%w[loop_association missing_counter_cache])
      end
    end

    context "with --no-color" do
      it "disables colored output" do
        cli = described_class.new([fixtures_path, "--no-color"])
        output = capture_stdout { cli.run }

        expect(output).not_to include("\e[")
      end
    end
  end

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
