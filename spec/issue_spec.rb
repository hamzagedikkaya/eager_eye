# frozen_string_literal: true

require "json"

RSpec.describe EagerEye::Issue do
  let(:valid_attributes) do
    {
      detector: :loop_association,
      file_path: "app/controllers/posts_controller.rb",
      line_number: 15,
      message: "Potential N+1 detected: `post.author` called inside loop"
    }
  end

  describe "#initialize" do
    it "creates an issue with required attributes" do
      issue = described_class.new(**valid_attributes)

      expect(issue.detector).to eq(:loop_association)
      expect(issue.file_path).to eq("app/controllers/posts_controller.rb")
      expect(issue.line_number).to eq(15)
      expect(issue.message).to eq("Potential N+1 detected: `post.author` called inside loop")
    end

    it "defaults severity to :warning" do
      issue = described_class.new(**valid_attributes)
      expect(issue.severity).to eq(:warning)
    end

    it "defaults suggestion to nil" do
      issue = described_class.new(**valid_attributes)
      expect(issue.suggestion).to be_nil
    end

    it "accepts custom severity" do
      issue = described_class.new(**valid_attributes, severity: :error)
      expect(issue.severity).to eq(:error)
    end

    it "accepts suggestion" do
      issue = described_class.new(**valid_attributes, suggestion: "Use includes(:author)")
      expect(issue.suggestion).to eq("Use includes(:author)")
    end

    it "raises ArgumentError for invalid severity" do
      expect { described_class.new(**valid_attributes, severity: :invalid) }
        .to raise_error(ArgumentError, /Invalid severity: invalid/)
    end
  end

  describe "#to_h" do
    it "returns a hash representation" do
      issue = described_class.new(**valid_attributes, suggestion: "Use includes(:author)")

      expect(issue.to_h).to eq(
        detector: :loop_association,
        file_path: "app/controllers/posts_controller.rb",
        line_number: 15,
        message: "Potential N+1 detected: `post.author` called inside loop",
        severity: :warning,
        suggestion: "Use includes(:author)"
      )
    end
  end

  describe "#to_json" do
    it "returns a JSON representation" do
      issue = described_class.new(**valid_attributes)
      parsed = JSON.parse(issue.to_json)

      expect(parsed["detector"]).to eq("loop_association")
      expect(parsed["file_path"]).to eq("app/controllers/posts_controller.rb")
      expect(parsed["line_number"]).to eq(15)
    end
  end

  describe "#==" do
    it "returns true for issues with same attributes" do
      issue1 = described_class.new(**valid_attributes)
      issue2 = described_class.new(**valid_attributes)

      expect(issue1).to eq(issue2)
    end

    it "returns false for issues with different attributes" do
      issue1 = described_class.new(**valid_attributes)
      issue2 = described_class.new(**valid_attributes, line_number: 20)

      expect(issue1).not_to eq(issue2)
    end

    it "returns false when compared with non-Issue object" do
      issue = described_class.new(**valid_attributes)

      expect(issue).not_to eq("not an issue")
    end
  end

  describe "#eql?" do
    it "is aliased to ==" do
      issue1 = described_class.new(**valid_attributes)
      issue2 = described_class.new(**valid_attributes)

      expect(issue1.eql?(issue2)).to be(true)
    end
  end

  describe "#hash" do
    it "returns same hash for equal issues" do
      issue1 = described_class.new(**valid_attributes)
      issue2 = described_class.new(**valid_attributes)

      expect(issue1.hash).to eq(issue2.hash)
    end

    it "can be used in sets" do
      issue1 = described_class.new(**valid_attributes)
      issue2 = described_class.new(**valid_attributes)

      set = Set.new([issue1, issue2])
      expect(set.size).to eq(1)
    end
  end

  describe ".from_h" do
    let(:full_hash) do
      {
        detector: :loop_association,
        file_path: "app/models/foo.rb",
        line_number: 12,
        message: "msg",
        severity: :error,
        suggestion: "do bar"
      }
    end

    it "rebuilds an Issue equal to one constructed directly" do
      from_h_issue = described_class.from_h(full_hash)
      direct = described_class.new(**full_hash)
      expect(from_h_issue).to eq(direct)
    end

    it "round-trips through to_h" do
      original = described_class.new(**full_hash)
      rebuilt = described_class.from_h(original.to_h)
      expect(rebuilt).to eq(original)
    end

    it "round-trips through JSON" do
      original = described_class.new(**full_hash)
      rebuilt = described_class.from_h(JSON.parse(original.to_json))
      expect(rebuilt).to eq(original)
    end

    it "coerces string detector to symbol" do
      issue = described_class.from_h(full_hash.merge(detector: "callback_query"))
      expect(issue.detector).to eq(:callback_query)
    end

    it "coerces string severity to symbol" do
      issue = described_class.from_h(full_hash.merge(severity: "error"))
      expect(issue.severity).to eq(:error)
    end

    it "defaults severity to :warning when missing" do
      issue = described_class.from_h(full_hash.except(:severity))
      expect(issue.severity).to eq(:warning)
    end

    it "raises KeyError when required field is missing" do
      expect { described_class.from_h(full_hash.except(:file_path)) }
        .to raise_error(KeyError)
    end
  end
end
