# Usando a imagem base do Jupyter
FROM docker.io/jupyter/base-notebook:python-3.7.6

# Instala pacotes necessários
RUN apt-get -y update && \
    apt-get install -y \
        dbus-x11 \
        xorg \
        x11-xserver-utils \
        xinit \
        wget \
        i3 \
        chromium-browser \
        feh \
    --no-install-recommends && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Baixa e instala o TurboVNC
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/2.2.6/turbovnc_2.2.6_amd64.deb/download" \
        -O turbovnc_2.2.6_amd64.deb && \
    apt-get install -y -q ./turbovnc_2.2.6_amd64.deb && \
    rm ./turbovnc_2.2.6_amd64.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# Concede permissão para o usuário jovyan
RUN chown -R 1000:100 /home/jovyan

# Configura o X11 e o i3
RUN echo "exec i3" > /root/.xinitrc && chmod +x /root/.xinitrc

# Configura variáveis para o Chromium
RUN echo "CHROMIUM_FLAGS='--no-sandbox --disable-gpu --disable-software-rasterizer'" >> /etc/environment

# Cria o diretório de configuração do i3
RUN mkdir -p /root/.config/i3

# Adiciona o arquivo de configuração do i3 para definir a imagem de fundo
RUN echo "exec --no-startup-id feh --bg-scale /caminho/para/sua/imagem.jpg" >> /root/.config/i3/config

# Comando de entrada do Docker
CMD ["startx"]
