class Srps < Formula
  desc "System Resource Protection Script (Ananicy-cpp + EarlyOOM + helpers)"
  homepage "https://github.com/Dicklesworthstone/system_resource_protection_script"
  url "https://github.com/Dicklesworthstone/system_resource_protection_script/archive/refs/heads/main.tar.gz"
  sha256 "03bbb626743420a570d9031094e9cf61c5a72bbfd1ab675a6556bbde6dfe3c88"
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
