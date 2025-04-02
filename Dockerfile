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

# 2. Instala IceWM + temas (versão mais recente disponível)
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        icewm \
        icewm-common \  # Pacote que substitui icewm-themes/icewm-utils
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 3. Baixa temas adicionais do IceWM diretamente do GitHub
RUN wget https://github.com/ice-wm/icewm-themes/archive/refs/heads/master.tar.gz -O /tmp/icewm-themes.tar.gz && \
    tar -xzf /tmp/icewm-themes.tar.gz -C /usr/share/icewm/themes/ --strip-components=1 && \
    rm /tmp/icewm-themes.tar.gz

# 4. Configuração padrão do IceWM
RUN mkdir -p /etc/skel/.icewm && \
    echo "Theme=\"win95/default.theme\"" > /etc/skel/.icewm/theme && \
    echo "TaskBarClockLeds=1" > /etc/skel/.icewm/preferences && \
    echo "ShowProgramsMenu=1" >> /etc/skel/.icewm/preferences

# 5. Instala TurboVNC (última versão estável)
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
