FROM jupyter/base-notebook:python-3.7.6

USER root

# Atualiza pacotes e instala apenas o essencial
RUN apt-get -y update && \
    apt-get install -y \
        dbus-x11 \
        xorg \
        x11-xserver-utils \
        xinit \
        wget \
        chromium-browser \
        build-essential \
        libx11-dev \
        libxext-dev \
        libxrandr-dev \
        libxinerama-dev \
        libxft-dev \
        libimlib2-dev \
        libpng-dev \
        libjpeg-dev \
        libxpm-dev \
        libxcomposite-dev \
        libxdamage-dev \
        libxrender-dev \
        git \
        autoconf \
        automake \
        libtool \
        pkg-config \
        gettext \
        autopoint \
        libsm-dev \
        libice-dev \
        libfribidi-dev && \
    apt-get install --no-install-recommends -y && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
    
# Instalação do IceWM 3.5 diretamente do código-fonte
WORKDIR /usr/local/src
RUN git clone --depth 1 --branch 3.5.0 https://github.com/ice-wm/icewm.git && \
    cd icewm && \
    ./autogen.sh && \
    ./configure && \
    make -j$(nproc) && \
    make install && \
    cd .. && rm -rf icewm

# Instala o TurboVNC
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" \
        -O turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    apt-get install -y -q ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    rm ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# Corrige permissões do diretório do usuário
RUN chown -R $NB_UID:$NB_GID $HOME

# Configura o IceWM como gerenciador de janelas padrão
RUN echo "exec icewm-session" > /root/.xinitrc && chmod +x /root/.xinitrc

# Configuração para rodar o Chromium sem problemas gráficos
RUN echo "CHROMIUM_FLAGS='--no-sandbox --disable-gpu --disable-software-rasterizer'" >> /etc/environment

# Adiciona arquivos extras, se necessário
ADD . /opt/install
RUN fix-permissions /opt/install

USER $NB_USER

RUN cd /opt/install && conda env update -n base --file environment.yml
