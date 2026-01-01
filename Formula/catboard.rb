class Catboard < Formula
  desc "Copy file contents to clipboard with PDF text extraction and OCR"
  homepage "https://github.com/VerilyPete/catboard"
  version "VERSION_PLACEHOLDER"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/VerilyPete/catboard/releases/download/v#{version}/catboard-v#{version}-aarch64-apple-darwin.tar.gz"
      sha256 "SHA256_PLACEHOLDER"
    end
  end

  def install
    bin.install "catboard"
    bin.install "catboard-ocr"
    pkgshare.install "Copy to Clipboard.workflow"
  end

  def caveats
    <<~EOS
      To enable Finder right-click integration, run:
        cp -r "#{pkgshare}/Copy to Clipboard.workflow" ~/Library/Services/

      Then right-click any file in Finder to see "Copy to Clipboard" under Quick Actions.
    EOS
  end

  test do
    assert_match "catboard", shell_output("#{bin}/catboard --version")
  end
end
