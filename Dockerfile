FROM blackarchlinux/blackarch:latest

USER root

# Atualiza pacotes e instala apenas o essencial
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
        dbus \  # Substituído dbus-x11 por dbus
        xorg-server \
        xorg-xinit \
        xorg-xrandr \
        xorg-xset \
        openbox \
        chromium \
        wget \
    && pacman -Scc --noconfirm

# Instala o TurboVNC
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" \
        -O turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    pacman -U --noconfirm ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    rm ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# Corrige permissões do diretório do usuário
RUN chown -R $NB_UID:$NB_GID $HOME

# Configura o Openbox como gerenciador de janelas padrão
RUN echo "exec openbox-session" > /root/.xinitrc && chmod +x /root/.xinitrc

# Configuração para rodar o Chromium sem problemas gráficos
RUN echo "CHROMIUM_FLAGS='--no-sandbox --disable-gpu --disable-software-rasterizer'" >> /etc/environment

# Adiciona arquivos extras, se necessário
ADD . /opt/install
RUN fix-permissions /opt/install

USER $NB_USER
RUN cd /opt/install && conda env update -n base --file environment.yml
