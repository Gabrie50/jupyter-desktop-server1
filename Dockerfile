FROM jupyter/base-notebook:python-3.7.6

USER root

# Atualiza pacotes e instala dependências essenciais
RUN apt-get -y update && \
    apt-get install -y \
        dbus-x11 \
        xorg \
        x11-xserver-utils \
        xinit \
        wget \
        software-properties-common \
        chromium-browser \
        build-essential \
        cmake \
        qt5-qmake \
        qtbase5-dev \
        qtchooser \
        qtbase5-dev-tools \
        lxqt-session \
        lxqt-panel \
        lxqt-config \
        lxqt-themes \
        lxqt-globalkeys \
        lxqt-notificationd \
        openbox \
        pcmanfm-qt \
    --no-install-recommends && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Instala o TurboVNC
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" \
        -O turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    apt-get install -y -q ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    rm ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# Corrige permissões do diretório do usuário
RUN chown -R $NB_UID:$NB_GID $HOME

# Configura o LXQt como gerenciador de janelas padrão
RUN echo "exec startlxqt" > /root/.xinitrc && chmod +x /root/.xinitrc

# Configuração para rodar o Chromium sem problemas gráficos
RUN echo "CHROMIUM_FLAGS='--no-sandbox --disable-gpu --disable-software-rasterizer'" >> /etc/environment

# Configuração do PCManFM para gerenciar a área de trabalho
RUN mkdir -p /root/.config/pcmanfm-qt/default/ && \
    echo "[Configuration]" > /root/.config/pcmanfm-qt/default/pcmanfm-qt.conf && \
    echo "desktop=1" >> /root/.config/pcmanfm-qt/default/pcmanfm-qt.conf

# Adiciona arquivos extras, se necessário
ADD . /opt/install
RUN fix-permissions /opt/install

USER $NB_USER
RUN cd /opt/install && conda env update -n base --file environment.yml
