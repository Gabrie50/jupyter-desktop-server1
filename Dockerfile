FROM jupyter/base-notebook:python-3.7.6

USER root

# Instalações básicas + dependências do Hyprland + Firefox + TurboVNC
RUN apt-get -y update && apt-get install -y \
    dbus-x11 \
    firefox \
    xorg \
    wl-clipboard \
    wget \
    git \
    build-essential \
    cmake \
    meson \
    ninja-build \
    wayland-protocols \
    libwayland-dev \
    libxkbcommon-dev \
    libinput-dev \
    libxcb1-dev \
    libxcb-keysyms1-dev \
    libxcb-xfixes0-dev \
    libxcb-composite0-dev \
    libxcb-render-util0-dev \
    libx11-xcb-dev \
    libxrender-dev \
    libdbus-1-dev \
    libpango1.0-dev \
    libglib2.0-dev \
    libevdev-dev \
    libudev-dev \
    foot \
    eww \
    pipewire \
    wireplumber \
    libpipewire-0.3-dev \
    && apt-get clean

# Clona o Hyprland com tudo configurado
RUN git clone https://github.com/hyprwm/Hyprland.git /opt/Hyprland && \
    mkdir -p /etc/xdg/hypr && \
    cp -r /opt/Hyprland/example/hyprland.conf /etc/xdg/hypr/hyprland.conf && \
    sed -i 's/animations = true/animations = false/' /etc/xdg/hypr/hyprland.conf

# Instala TurboVNC
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" -O turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    apt-get install -y ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    rm ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# Corrige permissões para o usuário do Jupyter
RUN chown -R $NB_UID:$NB_GID $HOME

ADD . /opt/install
RUN fix-permissions /opt/install

USER $NB_USER
RUN cd /opt/install && \
    conda env update -n base --file environment.yml
    
