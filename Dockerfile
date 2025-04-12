FROM quay.io/jupyter/base-notebook:2025-04-01

USER root

RUN apt-get -y -qq update && apt-get -y -qq install \
    dbus-x11 \
    xorg \
    kwin-x11 \
    sddm \
    kde-full \
    plasma-desktop \
    kio \
    kio-extras \
    kdegames \
    katomic \
    dolphin \
    konsole \
    kdeconnect \
    kde-config-cron \
    kinit \
    systemsettings \
    plasma-widgets-addons \
    firefox \
    curl \
    wget \
    nano \
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
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Define a variável de ambiente para o Wine
ENV WINEDLLOVERRIDES="mscoree,mshtml="

# Adiciona a chave do repositório do WineHQ
RUN wget -nc https://dl.winehq.org/wine-builds/winehq.key && \
    gpg --dearmor winehq.key && \
    mv winehq.key.gpg /etc/apt/trusted.gpg.d/winehq-archive.gpg

# Adiciona o repositório do WineHQ para o Ubuntu 22.04 (Jammy)
RUN add-apt-repository 'deb https://dl.winehq.org/wine-builds/ubuntu/ jammy main'

# Atualiza os pacotes e instala o WineHQ Stable
RUN apt-get update && apt-get install -y --install-recommends winehq-stable && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Mover a instalação do Wine para a pasta do TurboVNC
RUN mv /opt/wine /opt/TurboVNC/wine && \
    ln -s /opt/TurboVNC/wine /usr/local/bin/wine
    

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
    
