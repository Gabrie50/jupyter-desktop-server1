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
        i3 \
        i3status \  # Comentário precisa estar em outra linha, ou sem a barra invertida
        chromium-browser \
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

# Configura o i3 como gerenciador de janelas padrão
RUN mkdir -p /etc/skel/.config/i3 && \
    echo "exec i3" > /root/.xinitrc && chmod +x /root/.xinitrc

# Copia um arquivo de configuração do i3 para evitar o prompt inicial
RUN mkdir -p /home/jovyan/.config/i3 && \
    cp /etc/skel/.config/i3/config /home/jovyan/.config/i3/config && \
    chown -R jovyan:jovyan /home/jovyan/.config

# Configuração para rodar o Chromium sem problemas gráficos
RUN echo "CHROMIUM_FLAGS='--no-sandbox --disable-gpu --disable-software-rasterizer'" >> /etc/environment

# Adiciona arquivos extras, se necessário
ADD . /opt/install
RUN fix-permissions /opt/install

USER $NB_USER
RUN cd /opt/install && conda env update -n base --file environment.yml
