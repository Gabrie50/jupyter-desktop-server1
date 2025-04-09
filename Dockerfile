FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && apt install -y \
    dbus-x11 \
    xorg \
    firefox \
    sddm \
    kde-full \
    dolphin \
    konsole \
    curl \
    wget \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    ca-certificates \
    sudo \
    && apt clean && rm -rf /var/lib/apt/lists/*

ARG NB_USER=jovyan
ARG NB_UID=1000
RUN useradd -m -s /bin/bash -u $NB_UID $NB_USER && \
    echo "$NB_USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" -O turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    apt install -y ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    rm turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

ADD . /opt/install
RUN chown -R $NB_USER:$NB_USER /opt/install

USER $NB_USER
WORKDIR /home/$NB_USER

# Se for usar Conda, descomente esta parte depois de instalar o Miniconda
# RUN cd /opt/install && \
#     if [ -f environment.yml ]; then echo "Atualizando Conda..." && conda env update -n base -f environment.yml; fi
