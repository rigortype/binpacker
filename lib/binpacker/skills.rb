# frozen_string_literal: true

module Binpacker
  # Registry for the gem-shipped, user-facing agent skills. Skills live in the
  # gem's top-level skills/ directory, each as skills/<name>/SKILL.md.
  # See docs/adr/0003-agent-driven-install-and-skills.md.
  module Skills
    ROOT = File.expand_path("../../skills", __dir__)

    module_function

    # [{ name:, path: }], sorted by name.
    def list
      Dir.glob(File.join(ROOT, "*", "SKILL.md")).sort.map do |file|
        { name: File.basename(File.dirname(file)), path: file }
      end
    end

    def exist?(name)
      !path(name).nil?
    end

    # Absolute path of a skill's SKILL.md, or nil when unknown.
    def path(name)
      file = File.join(ROOT, name, "SKILL.md")
      File.file?(file) ? file : nil
    end

    # The SKILL.md body for a skill.
    def body(name)
      file = path(name)
      raise Error, "unknown skill: #{name}" unless file
      File.read(file)
    end
  end
end
