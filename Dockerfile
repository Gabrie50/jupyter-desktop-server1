FROM jupyter/base-notebook:python-3.7.6

USER root

# Atualiza e instala pacotes básicos + Hyprland dependências
RUN apt-get update && apt-get install -y \
    dbus-x11 \
    firefox \
    xorg \
    wayland-protocols \
    libinput-bin \
    libxkbcommon0 \
    libxcb-xinput0 \
    git \
    wl-clipboard \
    sudo \
    wget \
    meson \
    ninja-build \
    cmake \
    libegl-dev \
    libwayland-dev \
    libdrm-dev \
    libxkbcommon-dev \
    libpixman-1-dev \
    wayland-utils \
    libglib2.0-dev \
    libpango1.0-dev \
    libpng-dev \
    libavutil-dev \
    libavcodec-dev \
    libavformat-dev \
    libxcb-composite0-dev \
    libxcb-ewmh-dev \
    libxcb-icccm4-dev \
    libxcb-image0-dev \
    libxcb-keysyms1-dev \
    libxcb-randr0-dev \
    libxcb-xfixes0-dev \
    libxcb-shape0-dev \
    libxcb-xinerama0-dev \
    libx11-xcb-dev \
    libxcb-util0-dev

# Clona o Hyprland
RUN git clone --recursive https://github.com/hyprwm/Hyprland.git /opt/Hyprland && \
    cd /opt/Hyprland && \
    make all && make install

# Instala TurboVNC
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" -O turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    apt-get install -y -q ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    rm ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# Ajusta permissões da home
RUN chown -R $NB_UID:$NB_GID $HOME

# Copia arquivos adicionais (como environment.yml, hyprland.conf custom, etc)
ADD . /opt/install
RUN fix-permissions /opt/install

# Volta para o usuário padrão do Jupyter
USER $NB_USER

# Instala dependências do conda
RUN cd /opt/install && \
    conda env update -n base --file environment.yml
    
