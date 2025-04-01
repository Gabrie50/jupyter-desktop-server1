FROM blackarchlinux/blackarch:latest

# Define o usuário root para instalação de pacotes
USER root

# Atualiza pacotes essenciais
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
        dbus \
        xorg-server \
        xorg-xinit \
        xorg-xrandr \
        xorg-xset \
        openbox \
        chromium \
        wget \
        sudo \
    && pacman -Scc --noconfirm

# Criação do usuário NB_USER (Jupyter padrão)
ARG NB_USER=jovyan
ARG NB_UID=1000
ARG NB_GID=1000

RUN groupadd --gid $NB_GID $NB_USER && \
    useradd --uid $NB_UID --gid $NB_GID -m -s /bin/bash $NB_USER && \
    echo "$NB_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$NB_USER

# Instalação do TurboVNC corretamente
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/2.2.6/turbovnc-2.2.6.x86_64.tar.gz" -O turbovnc.tar.gz && \
    tar -xzf turbovnc.tar.gz -C /opt && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/ && \
    rm turbovnc.tar.gz

# Configuração do Openbox como gerenciador de janelas padrão
RUN echo "exec openbox-session" > /root/.xinitrc && chmod +x /root/.xinitrc

# Configuração para rodar o Chromium corretamente
RUN echo "CHROMIUM_FLAGS='--no-sandbox --disable-gpu --disable-software-rasterizer'" >> /etc/environment

# Adiciona arquivos extras, se necessário
ADD . /opt/install
RUN chown -R $NB_UID:$NB_GID /opt/install

# Muda para o usuário NB_USER
USER $NB_USER

# Atualiza e configura o Conda
RUN cd /opt/install && conda env update -n base --file environment.yml

CMD ["openbox-session"]
