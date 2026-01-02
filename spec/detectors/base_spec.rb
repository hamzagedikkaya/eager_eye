# frozen_string_literal: true

RSpec.describe EagerEye::Detectors::Base do
  let(:detector) { described_class.new }

  describe ".detector_name" do
    it "raises NotImplementedError" do
      expect { described_class.detector_name }
        .to raise_error(NotImplementedError, "Subclasses must implement .detector_name")
    end
  end

  describe ".default_severity" do
    it "returns :warning" do
      expect(described_class.default_severity).to eq(:warning)
    end
  end

  describe "#detect" do
    it "raises NotImplementedError" do
      expect { detector.detect(nil, "test.rb") }
        .to raise_error(NotImplementedError, "Subclasses must implement #detect")
    end
  end

  describe "#create_issue" do
    let(:test_detector_class) do
      Class.new(described_class) do
        def self.detector_name
          :test_detector
        end

        def public_create_issue(**args)
          create_issue(**args)
        end
      end
    end

    let(:test_detector) { test_detector_class.new }

    it "creates an Issue with detector name" do
      issue = test_detector.public_create_issue(
        file_path: "app/models/user.rb",
        line_number: 10,
        message: "Test issue"
      )

      expect(issue).to be_a(EagerEye::Issue)
      expect(issue.detector).to eq(:test_detector)
      expect(issue.file_path).to eq("app/models/user.rb")
      expect(issue.line_number).to eq(10)
      expect(issue.message).to eq("Test issue")
      expect(issue.severity).to eq(:warning)
      expect(issue.suggestion).to be_nil
    end

    it "accepts custom severity and suggestion" do
      issue = test_detector.public_create_issue(
        file_path: "app/models/user.rb",
        line_number: 10,
        message: "Test issue",
        severity: :error,
        suggestion: "Fix this"
      )

      expect(issue.severity).to eq(:error)
      expect(issue.suggestion).to eq("Fix this")
    end
  end

  describe "#traverse_ast" do
    let(:test_detector_class) do
      Class.new(described_class) do
        def self.detector_name
          :test_detector
        end

        def public_traverse_ast(node, &block)
          traverse_ast(node, &block)
        end

        def public_parse_source(source)
          parse_source(source)
        end
      end
    end

    let(:test_detector) { test_detector_class.new }

    it "yields each node in the AST" do
      source = "def foo; bar; end"
      ast = test_detector.public_parse_source(source)
      nodes = []

      test_detector.public_traverse_ast(ast) { |node| nodes << node.type }

      expect(nodes).to include(:def, :send)
    end

    it "handles nil gracefully" do
      nodes = []
      test_detector.public_traverse_ast(nil) { |node| nodes << node }

      expect(nodes).to be_empty
    end

    it "handles non-Node children gracefully" do
      source = "x = 1"
      ast = test_detector.public_parse_source(source)
      nodes = []

      expect { test_detector.public_traverse_ast(ast) { |node| nodes << node.type } }
        .not_to raise_error
    end
  end

  describe "#parse_source" do
    let(:test_detector_class) do
      Class.new(described_class) do
        def self.detector_name
          :test_detector
        end

        def public_parse_source(source)
          parse_source(source)
        end
      end
    end

    let(:test_detector) { test_detector_class.new }

    it "parses valid Ruby source" do
      ast = test_detector.public_parse_source("def foo; end")

      expect(ast).to be_a(Parser::AST::Node)
      expect(ast.type).to eq(:def)
    end

    it "returns nil for invalid syntax" do
      ast = test_detector.public_parse_source("def foo")

      expect(ast).to be_nil
    end
  end
end
