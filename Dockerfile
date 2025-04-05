FROM ubuntu:22.04

USER root

# Atualizando pacotes e instalando dependências
RUN apt-get -y update && apt-get install -y \
    dbus-x11 \
    firefox \
    wget \
    xorg \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    curl \
    gnupg2 \
    ca-certificates \
    software-properties-common

# Adicionando repositórios para Wayland e outros pacotes
RUN add-apt-repository ppa:wayland-packages/wayland && apt-get update

# Instalando o Wayland e outros pacotes necessários
RUN apt-get install -y \
    wayland-protocols

# Instalando o Hyprland a partir do código-fonte
RUN curl -sSL https://github.com/hyprwm/Hyprland/releases/download/v0.0.9/Hyprland-0.0.9.tar.gz | tar -xzv -C /tmp && \
    cd /tmp/Hyprland && \
    make && \
    make install

# Instalando o Eww a partir do repositório GitHub
RUN git clone https://github.com/elkowar/eww.git /tmp/eww && \
    cd /tmp/eww && \
    make && \
    sudo make install

# Baixar e instalar o TurboVNC
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" -O turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    apt-get install -y -q ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    apt-get remove -y -q light-locker && \
    rm ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# Conceder permissões corretas ao diretório HOME
RUN chown -R $NB_UID:$NB_GID $HOME

USER $NB_USER
