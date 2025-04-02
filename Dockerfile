FROM jupyter/base-notebook:python-3.9

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
        ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Instala IceWM + temas
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        icewm \
        icewm-common && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 3. Baixa temas adicionais do IceWM
RUN git clone https://github.com/ice-wm/icewm-themes.git /usr/share/icewm/themes/

# 4. Configuração padrão do IceWM
RUN mkdir -p /etc/skel/.icewm && \
    echo "Theme=\"win95/default.theme\"" > /etc/skel/.icewm/theme && \
    echo "TaskBarClockLeds=1" > /etc/skel/.icewm/preferences && \
    echo "ShowProgramsMenu=1" >> /etc/skel/.icewm/preferences

# 5. Instala TurboVNC
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb" -O turbovnc.deb && \
    apt-get install -y -q ./turbovnc.deb && \
    rm ./turbovnc.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# 6. Instala Chromium
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        chromium-browser \
        chromium-codecs-ffmpeg-extra \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 7. Configurações finais
RUN echo "CHROMIUM_FLAGS='--no-sandbox --disable-gpu --disable-software-rasterizer'" >> /etc/environment && \
    echo "exec icewm-session" > /etc/skel/.xinitrc && \
    chmod +x /etc/skel/.xinitrc

# 8. Corrige permissões
RUN chown -R $NB_UID:$NB_GID /home/$NB_USER && \
    fix-permissions /home/$NB_USER

USER $NB_USER

# 9. (Opcional) Configuração de ambiente conda
COPY environment.yml /tmp/
RUN conda env update -n base --file /tmp/environment.yml && \
    rm /tmp/environment.yml
    
