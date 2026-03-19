class Tasuki < Formula
  desc "Multi-agent orchestration framework for AI-assisted development"
  homepage "https://github.com/ForeroAlexander/Tasuki"
  url "https://github.com/ForeroAlexander/Tasuki/archive/refs/tags/v1.1.0.tar.gz"
  sha256 "a6868ac0dc72faad1b26524943103c9d4385862a42ae9175c4679fc4a2a2fac0"
  license "MIT"

  depends_on "python@3"
  depends_on "bash"

  def install
    # Install all source files
    libexec.install Dir["*"]

    # Create wrapper script that points to the real binary
    (bin/"tasuki").write <<~EOS
      #!/bin/bash
      exec "#{libexec}/bin/tasuki" "$@"
    EOS
  end

  test do
    system "#{bin}/tasuki", "--version"
  end
end
