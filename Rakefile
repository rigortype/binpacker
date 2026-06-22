# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

# ---------------------------------------------------------------
# GitHub Release automation
# ---------------------------------------------------------------
#
# `bundler/gem_tasks` provides `rake release` (guard-clean →
# build → tag → push → rubygems_push). We layer
# `rake release:github` on top: it reads the matching CHANGELOG
# section verbatim and creates a GitHub Release whose title is
# the section heading (`[x.y.z] - YYYY-MM-DD`) and whose body
# is the section text plus a `**Full Changelog**:` compare link.
#
# Hooked via `Rake::Task["release"].enhance do … end` so a full
# `rake release` invocation also creates the GitHub Release.
# Runs standalone as `rake release:github` to retry just this
# step when `rake release` succeeded but `gh release create`
# didn't (e.g. transient gh / network failure).
GITHUB_RELEASE_REPO = "rigortype/binpacker"

namespace :release do
  desc "Create a GitHub Release from the matching CHANGELOG.md section"
  task :github do
    require "English"
    require_relative "lib/binpacker/version"
    version = Binpacker::VERSION
    tag = "v#{version}"

    unless system("git", "rev-parse", "--verify", "--quiet", "#{tag}^{tag}", out: File::NULL)
      abort "tag #{tag} not found locally — run `bundle exec rake release` first"
    end

    section = ReleaseHelpers.extract_changelog_section(version, "CHANGELOG.md")
    abort "no CHANGELOG section for [#{version}]" unless section

    title, body = section
    prev_tag = `git describe --tags --abbrev=0 "#{tag}^"`.strip
    notes = if prev_tag.empty? || !$CHILD_STATUS.success?
      "#{body}\n"
    else
      compare = "https://github.com/#{GITHUB_RELEASE_REPO}/compare/#{prev_tag}...#{tag}"
      "#{body}\n\n**Full Changelog**: #{compare}\n"
    end

    require "tempfile"
    Tempfile.create(["binpacker-release-notes-", ".md"]) do |f|
      f.write(notes)
      f.flush
      sh "gh", "release", "create", tag, "--title", title, "--notes-file", f.path
    end
  end
end

module ReleaseHelpers
  module_function

  def extract_changelog_section(version, path)
    in_section = false
    title = nil
    body_lines = []

    File.foreach(path, encoding: "UTF-8") do |line|
      if line.start_with?("## [")
        break if in_section

        if line =~ /^## \[#{Regexp.escape(version)}\] - /
          in_section = true
          title = line.sub(/^## /, "").strip
          next
        end
      end
      body_lines << line if in_section
    end

    return nil unless title

    [title, body_lines.join.strip]
  end
end

Rake::Task["release"].enhance do
  Rake::Task["release:github"].invoke
end
