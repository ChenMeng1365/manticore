# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "manticore-smash"
  spec.version       = "3.3.0"
  spec.authors       = ["Frampt"]
  spec.summary       = "A multi-format toolkit"
  spec.description   = "A multi-format library for parsing, formatting, interacting and more."
  spec.homepage      = "https://github.com/ChenMeng1365/manticore"
  spec.license       = "AGPL-3.0-or-later"
  spec.required_ruby_version = ">= 3.0"
  spec.files         = Dir["lib/**/*.rb"] + Dir["bin/*"] + ["LICENSE", "README.md"]
  spec.require_paths = ["lib"]
end
