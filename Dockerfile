FROM quay.io/jupyter/base-notebook:2025-04-01

USER root

RUN apt-get -y -qq update && apt-get -y -qq install \
    dbus-x11 \
    kwin-x11 \
    xorg \
    firefox \
    sddm \
    kde-full \
    kdeedu \
    kdegames \
    ksudoku \
    kde-full \
    dolphin \
    konsole \
    kolf \
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
    
