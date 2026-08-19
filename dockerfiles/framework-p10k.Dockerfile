# oh-my-zsh plus the prompt everyone pairs it with. powerlevel10k is the
# sharpest test of the array base: it is thousands of lines of zsh that all
# assume the native one.
#
# BASE is the sshd image from sshd-debian.Dockerfile; the framework goes on
# top of it and hitest keeps that image's login shell.
ARG BASE=hi-test-sshd
FROM ${BASE}
RUN apt-get update -qq && apt-get install -y -qq zsh curl ca-certificates git >/dev/null
USER hitest
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
 && git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/custom/themes/powerlevel10k \
 && sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' ~/.zshrc \
 && printf 'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true\n' >>~/.zshrc
USER root
