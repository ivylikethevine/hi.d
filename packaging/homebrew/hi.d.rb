# The tap formula. Publish by copying this file to Formula/hi.d.rb in a repo
# named ivylikethevine/homebrew-tap; `brew install ivy/tap/hi.d` then works with
# no review and no approval. packaging/bump.sh rewrites the url and sha256.
#
# hi.d.rb -> class HiD: Homebrew's Formulary.class_s camel-cases across the dot.
class HiD < Formula
  desc "sshrc supercharged - your shell config, on every host you say hi to"
  homepage "https://github.com/ivylikethevine/hi.d"
  url "https://github.com/ivylikethevine/hi.d/archive/refs/tags/v0.0.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  head "https://github.com/ivylikethevine/hi.d.git", branch: "main"

  uses_from_macos "openssh"
  # No armor dependency. hi armors the ssh bootstrap payload with `base64`,
  # which macOS has always shipped (and so does every Linux base system this
  # formula could land on).
  #
  # No `depends_on "bash"` either: hi is written for bash 3.2 precisely so that
  # macOS's own /bin/bash can run it.

  def install
    # This list is _HI_PACKAGE_CONTENTS in scripts/install.sh, repeated because
    # a formula cannot call install.sh: install_tree hardcodes /usr/bin and
    # /etc/profile.d, neither of which exists inside a brew prefix. The
    # packaging suite (tests/scripts/packaging_test.sh) fails if the two lists
    # drift apart.
    #
    # It must land in a directory named hi.d - every path in the project
    # resolves against $_HI_HOME/hi.d, so libexec is the _HI_HOME here.
    (libexec/"hi.d").install "common", "misc", "scripts", "shells",
                             "hi.sh", "load.sh", "LICENSE", "README.md"
    chmod 0755, libexec/"hi.d/hi.sh"

    # A wrapper rather than bin.install_symlink: hi.sh sources
    # "${_HI_HOME:-$HOME}/hi.d/common/core.sh" and never locates itself, so a
    # bare symlink on PATH would look for the tree in $HOME and find nothing.
    (bin/"hi").write <<~SH
      #!/bin/sh
      export _HI_HOME="#{libexec}"
      exec "#{libexec}/hi.d/hi.sh" "$@"
    SH
  end

  def caveats
    <<~EOS
      `hi` is on your PATH now, but your shells are not wired up yet. To get the
      header, prompt, aliases and editor configs in your own shells, run:

        #{libexec}/hi.d/scripts/install.sh --no-link

      That writes only to your rc files and ~/.config/hi.d - never into the keg.
      --no-link is what skips the /usr/bin/hi symlink: Homebrew already put `hi`
      on your PATH, and on macOS /usr/bin is read-only under SIP anyway.

      Re-run it as `hi_configure` any time to revisit the feature toggles.
      `hi_update` will tell you to update through Homebrew, which is correct -
      run `brew upgrade hi.d` instead.
    EOS
  end

  test do
    # The wiring that actually matters and the thing most likely to break: the
    # tree is where _HI_HOME says it is, and sourcing core.sh from the keg
    # resolves _HI_ROOT back to the keg rather than to $HOME.
    assert_equal "#{libexec}/hi.d", shell_output(
      "_HI_HOME=#{libexec} /bin/bash -c 'source #{libexec}/hi.d/common/core.sh; printf %s \"$_HI_ROOT\"'",
    )

    # ...and that the wrapper exports it for a caller who has not.
    assert_match libexec.to_s, (bin/"hi").read
  end
end
