# frozen_string_literal: true

require "spec_helper"
require "binpacker/skills"

RSpec.describe Binpacker::Skills do
  describe ".list" do
    it "lists the bundled user-facing skills" do
      names = described_class.list.map { |s| s[:name] }
      expect(names).to include("binpacker-setup", "binpacker-improve")
    end

    it "returns absolute paths to SKILL.md files" do
      described_class.list.each do |skill|
        expect(File.file?(skill[:path])).to be true
        expect(File.basename(skill[:path])).to eq("SKILL.md")
      end
    end
  end

  describe ".path" do
    it "returns the SKILL.md path for a known skill" do
      expect(described_class.path("binpacker-setup")).to end_with("binpacker-setup/SKILL.md")
    end

    it "returns nil for an unknown skill" do
      expect(described_class.path("nope")).to be_nil
    end
  end

  describe ".body" do
    it "returns the SKILL.md contents" do
      expect(described_class.body("binpacker-setup")).to include("# Binpacker Setup")
    end

    it "raises for an unknown skill" do
      expect { described_class.body("nope") }.to raise_error(Binpacker::Error)
    end
  end
end
