FROM jupyter/base-notebook:python-3.7.6

USER root

# 1. Instala dependências básicas e X11
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
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Instala IceWM 1.6 (versão mais recente)
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        icewm \
        icewm-themes \
        icewm-utils \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 3. Configuração do IceWM (tema e preferências)
RUN mkdir -p /etc/skel/.icewm && \
    echo "Theme=\"SilverXP/default.theme\"" > /etc/skel/.icewm/theme && \
    echo "TaskBarClockLeds=1" > /etc/skel/.icewm/preferences && \
    echo "ShowProgramsMenu=1" >> /etc/skel/.icewm/preferences

# 4. Instala TurboVNC (última versão estável)
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" \
        -O turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    apt-get install -y -q ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    rm ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# 5. Instala Chromium com suporte a GPU (opcional)
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        chromium-browser \
        chromium-codecs-ffmpeg-extra \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 6. Configurações de ambiente
RUN echo "CHROMIUM_FLAGS='--no-sandbox --disable-gpu --disable-software-rasterizer'" >> /etc/environment && \
    echo "exec icewm-session" > /etc/skel/.xinitrc && \
    chmod +x /etc/skel/.xinitrc

# 7. Configura permissões e usuário
RUN chown -R $NB_UID:$NB_GID /home/$NB_USER && \
    fix-permissions /home/$NB_USER

USER $NB_USER

# 8. (Opcional) Instalação de pacotes adicionais via conda
COPY environment.yml /tmp/
RUN conda env update -n base --file /tmp/environment.yml && \
    rm /tmp/environment.yml
