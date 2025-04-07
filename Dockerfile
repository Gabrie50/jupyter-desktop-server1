FROM quay.io/jupyter/base-notebook:2025-04-01

USER root

# Atualizando pacotes e instalando ambiente gráfico leve e bonito
RUN apt-get -y -qq update && apt-get -y -qq install \
    dbus-x11 \
    xorg \
    firefox \
    kde-plasma-desktop \
    dolphin \
    konsole \
    plank \
    tint2 \
    conky \
    curl \
    wget \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    ca-certificates \
    --no-install-recommends && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Instalação do Jupyter
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3 && \
    pip3 install --no-cache-dir jupyter

# Baixar e instalar TurboVNC
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" -O turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    apt-get install -y -q ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    rm ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# Corrigir permissões
RUN chown -R $NB_UID:$NB_GID $HOME

# Copiando arquivos de instalação
ADD . /opt/install
RUN fix-permissions /opt/install

USER $NB_USER

# Atualizando o Conda (se houver environment.yml)
RUN cd /opt/install && conda env update -n base --file environment.yml || true
