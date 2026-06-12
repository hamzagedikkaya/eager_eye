# frozen_string_literal: true

RSpec.describe EagerEye::SchemaParser do
  let(:parser) { described_class.new }
  let(:app_path) { File.expand_path("fixtures/schema_app/app", __dir__) }

  describe "#parse_from_path" do
    it "finds db/schema.rb by walking up from the given path" do
      expect(parser.parse_from_path(app_path)).to be(true)
    end

    it "returns false when no schema is found" do
      expect(parser.parse_from_path("/")).to be(false)
    end

    it "collects every column across tables" do
      parser.parse_from_path(app_path)
      expect(parser.all_columns).to include(:comsn_rate, :vat_rate, :service_fee_rate, :name)
    end

    it "captures reference columns as <name>_id" do
      parser.parse_from_path(app_path)
      expect(parser.all_columns).to include(:end_of_day_report_id)
    end

    it "maps columns onto the model a table classifies to" do
      parser.parse_from_path(app_path)
      expect(parser.columns_by_model["EodItem"]).to include(:comsn_rate, :vat_rate)
      expect(parser.columns_by_model["Merchant"]).to include(:service_fee_rate)
    end
  end
end
