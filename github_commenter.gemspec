# coding: utf-8
Gem::Specification.new do |spec|
  spec.name          = "github_commenter"
  spec.version       = File.read(File.expand_path("../VERSION", __FILE__)).chomp
  spec.authors       = ["okitan"]
  spec.email         = ["okitakunio@gmail.com"]

  spec.summary       = "CLI to comment github"
  spec.description   = "CLI to comment github PR/commit"
  spec.homepage      = "TODO: Put your gem's website or public repo URL here."
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "addressable"
  spec.add_dependency "git_diff_parser"
  spec.add_dependency "ltsv"
  spec.add_dependency "octokit"
  spec.add_dependency "thor"

  spec.add_development_dependency "bundler", "~> 1.12"
  spec.add_development_dependency "rake", "~> 10.0"
end
