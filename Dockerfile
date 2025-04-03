FROM alpine:latest

USER root

# Atualiza pacotes e instala dependências essenciais
RUN apk update && apk add --no-cache \
    dbus-x11 \
    xorg-server \
    xinit \
    wget \
    chromium \
    build-base \
    libx11-dev \
    libxext-dev \
    libxrandr-dev \
    libxinerama-dev \
    libxft-dev \
    imlib2-dev \
    libpng-dev \
    libjpeg-turbo-dev \
    libxpm-dev \
    libxcomposite-dev \
    libxdamage-dev \
    libxrender-dev \
    git \
    autoconf \
    automake \
    libtool \
    pkgconf \
    gettext \
    gettext-dev \
    libsm-dev \
    libice-dev \
    fribidi-dev \
    markdown \
    asciidoctor

# Instalação do IceWM 3.5 diretamente do código-fonte
WORKDIR /usr/local/src
RUN git clone --depth 1 --branch 3.5.0 https://github.com/ice-wm/icewm.git && \
    cd icewm && \
    autoreconf -i && \
    ./configure && \
    make -j$(nproc) && \
    make install && \
    cd .. && rm -rf icewm

# Instala o TurboVNC
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc.x86_64.tar.gz/download" \
        -O turbovnc.tar.gz && \
    tar -xzf turbovnc.tar.gz -C /opt/ && \
    rm turbovnc.tar.gz && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# Configuração do IceWM
RUN echo "exec icewm-session" > /root/.xinitrc && chmod +x /root/.xinitrc

# Configuração para rodar o Chromium sem problemas gráficos
RUN echo "CHROMIUM_FLAGS='--no-sandbox --disable-gpu --disable-software-rasterizer'" >> /etc/environment

# Adiciona arquivos extras, se necessário
ADD . /opt/install

USER 1000

RUN cd /opt/install && conda env update -n base --file environment.yml
