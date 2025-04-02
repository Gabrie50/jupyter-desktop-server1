FROM jupyter/base-notebook:python-3.9

# 1. Atualiza o sistema e instala pacotes necessários
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        dbus-x11 \
        xorg \
        x11-xserver-utils \
        xinit \
        wget \
        git \
        mesa-utils \
        libgl1-mesa-dri \
        fonts-dejavu \
        pulseaudio \
        pavucontrol \
        network-manager \
        net-tools \
        ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Instala o IceWM
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        icewm \
        icewm-common && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 3. Baixa e instala os temas do IceWM sem necessidade de autenticação
RUN rm -rf /usr/share/icewm/themes && \
    wget -qO- https://github.com/ice-wm/icewm-themes/archive/refs/heads/master.tar.gz | tar -xz -C /usr/share/icewm/ && \
    mv /usr/share/icewm/icewm-themes-master /usr/share/icewm/themes

# 4. Configuração padrão do IceWM (adicione comandos extras se necessário)
# COPY arquivos_de_config /usr/share/icewm/

CMD ["icewm"]
