# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "manticore"
  spec.version       = "3.0.1"
  spec.authors       = ["Manticore"]
  spec.summary       = "A multi-format toolkit"
  spec.description   = "A multi-format library for parsing, formatting, interacting and more."
  spec.homepage      = "https://github.com/ChenMeng1365/manticore"
  spec.license       = "AGPL-3.0-or-later"
  spec.required_ruby_version = ">= 3.0"
  spec.files         = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]
end
