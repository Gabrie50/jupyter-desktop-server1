FROM jupyter/base-notebook:python-3.7.6

USER root

# Atualizando pacotes
RUN apt-get -y update && apt-get install -y \
    dbus-x11 \
    firefox \
    wget \
    xorg \
    build-essential \
    cmake \
    git \
    libwayland-dev \
    libx11-dev \
    libxrandr-dev \
    libinput-dev \
    libevdev-dev \
    libxcb-xfixes0-dev

# Corrigir o caminho dos arquivos para remover espaços
ADD Hyprland_Wayland/Hyprland /opt/Hyprland
ADD Hyprland_Wayland/foot /opt/foot
ADD Hyprland_Wayland/eww /opt/eww

# Instalar o Hyprland
RUN cd /opt/Hyprland && make install

# Instalar foot e eww
RUN tar -xzf /opt/foot/foot-1.10.0-x86_64-linux.tar.gz -C /opt/ && \
    ln -s /opt/foot-1.10.0/bin

RUN cd /opt/eww && make && make install

# Baixar e instalar o TurboVNC
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" -O turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    apt-get install -y -q ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    apt-get remove -y -q light-locker && \
    rm ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# Conceder permissões corretas ao diretório HOME
RUN chown -R $NB_UID:$NB_GID $HOME

# Adicionando o diretório de instalação
ADD . /opt/install
RUN fix-permissions /opt/install

USER $NB_USER

# Atualizar o ambiente Conda
RUN cd /opt/install && conda env update -n base --file environment.yml
