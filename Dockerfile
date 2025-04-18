FROM quay.io/jupyter/base-notebook:2025-04-01


USER root

RUN apt-get update && apt-get install -y \
    dbus-x11 \
    qutebrowser \
    libnss3 \
    libxss1 \
    libasound2t64 \
    libatk-bridge2.0-0 \
    libgtk-3-0 
   


RUN apt-get -y -qq update && apt-get -y -qq install \
    dbus-x11 \
    xserver-xorg \
    xfce4 \
    xfce4-goodies \
    lightdm \
    policykit-1 \
    xinit \
    xdg-user-dirs \
    xdg-utils \
    network-manager \
    alsa-utils \
    pulseaudio \
    fonts-dejavu \
    fonts-liberation \
    fonts-noto \
    fonts-noto-cjk \
    fonts-noto-color-emoji \
    plank \
    winetricks \
    libvulkan1 \
    mesa-vulkan-drivers \
    vulkan-tools \
    wget \
    git \
    nano \
    curl \
    unzip \
    htop \
    sudo \
    bash \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    ca-certificates \
    --no-install-recommends && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
    


    
# Instalar TurboVNC
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" -O turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    apt-get install -y ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    rm turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# Adiciona a arquitetura i386 necessária para o Wine
RUN dpkg --add-architecture i386

# Instala dependências necessárias
RUN apt-get update && apt-get install -y --no-install-recommends \
        software-properties-common \
        wget \
        gnupg2 \
    && rm -rf /var/lib/apt/lists/*

# Define variável de ambiente do Wine
ENV WINEDLLOVERRIDES="mscoree,mshtml="

# Adiciona a chave do WineHQ
RUN wget -nc https://dl.winehq.org/wine-builds/winehq.key && \
    gpg --dearmor winehq.key && \
    install -o root -g root -m 644 winehq.key.gpg /etc/apt/trusted.gpg.d/winehq-archive.gpg && \
    rm winehq.key winehq.key.gpg

# Adiciona o repositório do WineHQ para Ubuntu 22.04
RUN add-apt-repository 'deb https://dl.winehq.org/wine-builds/ubuntu/ jammy main'

# Instala o Wine
RUN apt-get update && apt-get install -y --install-recommends winehq-stable && \
    rm -rf /var/lib/apt/lists/*

# Cria o atalho .desktop do Wine
RUN mkdir -p /usr/share/applications && \
    printf "[Desktop Entry]\nName=Wine\nExec=wine start /unix %%f\nType=Application\nStartupNotify=true\nTerminal=false\nIcon=wine\nCategories=Utility;Application;\n" \
    > /usr/share/applications/wine.desktop && \
    chmod +x /usr/share/applications/wine.desktop
    
    

    

# Garantir permissões corretas ao diretório HOME
RUN chown -R $NB_UID:$NB_GID $HOME

# Adicionar os arquivos do projeto (ex: xstartup, environment.yml, etc.)
ADD . /opt/install
RUN fix-permissions /opt/install

USER $NB_USER
WORKDIR /home/$NB_USER

# Atualizar Conda se environment.yml existir
RUN cd /opt/install && \
    if [ -f environment.yml ]; then conda env update -n base --file environment.yml; fi


USER jovyan

RUN mkdir -p /home/jovyan/.config/qutebrowser && \
    echo "c.qt.args = ['--disable-sandbox']" >> /home/jovyan/.config/qutebrowser/config.py
       
    
