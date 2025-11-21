class Srps < Formula
  desc "System Resource Protection Script (Ananicy-cpp + EarlyOOM + helpers)"
  homepage "https://github.com/Dicklesworthstone/system_resource_protection_script"
  url "https://github.com/Dicklesworthstone/system_resource_protection_script/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "358db139fdf87c616a0f64a0448df9b6794ba394a5376b1dc8eca3ec1437784b"
  license "MIT"

  depends_on "bash"
  depends_on "git"

  def install
    libexec.install "install.sh", "verify.sh", "README.md"
    bin.install_symlink libexec/"install.sh" => "srps-install"
    bin.install_symlink libexec/"verify.sh" => "srps-verify"
  end

  def caveats
    <<~EOS
      Usage:
        srps-verify latest   # verify release integrity
        srps-install --plan  # dry-run the installer
        srps-install         # run installer (prompts for sudo)

      Note: installer makes system-wide changes (ananicy rules, EarlyOOM config, sysctl).
    EOS
  end

  test do
    assert_predicate libexec/"install.sh", :exist?
  end
end
