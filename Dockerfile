FROM jupyter/base-notebook:python-3.7.6

USER root

# Atualiza e instala dependências essenciais
RUN apt-get update && apt-get install -y \
    dbus-x11 \
    firefox \
    xorg \
    wayland-protocols \
    libgtk-3-dev \
    libpango1.0-dev \
    libgdk-pixbuf2.0-dev \
    libglib2.0-dev \
    libcairo2-dev \
    scdoc \
    cargo \
    clang \
    git \
    cmake \
    meson \
    ninja-build \
    libwayland-dev \
    libxkbcommon-dev \
    libxcb1-dev \
    libxcb-keysyms1-dev \
    libxcb-xfixes0-dev \
    libpixman-1-dev \
    libegl1-mesa-dev \
    libdrm-dev \
    libgbm-dev \
    libinput-dev \
    libx11-dev \
    libgl1-mesa-dev \
    libxrandr-dev \
    libxcb-render0-dev \
    libxcb-shape0-dev \
    libxcb-xinerama0-dev \
    libxcb-util0-dev \
    libxcb-cursor-dev \
    libxcb-icccm4-dev \
    libxcb-ewmh-dev \
    wget

# Compilar e instalar foot terminal
RUN git clone https://codeberg.org/dnkl/foot.git /opt/foot && \
    cd /opt/foot && \
    meson setup build && \
    ninja -C build && \
    ninja -C build install && \
    rm -rf /opt/foot

# Clonar e compilar Hyprland
RUN git clone --recursive https://github.com/hyprwm/Hyprland.git /opt/Hyprland && \
    cd /opt/Hyprland && \
    make all && make install && \
    rm -rf /opt/Hyprland

# Clonar e instalar Eww com widgets
RUN git clone https://github.com/elkowar/eww.git /opt/eww && \
    cd /opt/eww && \
    cargo build --release && \
    install -Dm755 target/release/eww /usr/local/bin/eww && \
    rm -rf /opt/eww

# TurboVNC
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" -O turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    apt-get install -y ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    rm ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# xstartup com Hyprland
RUN mkdir -p /root/.vnc && echo '#!/bin/bash\nexec Hyprland' > /root/.vnc/xstartup && chmod +x /root/.vnc/xstartup

# Permissões
RUN chown -R $NB_UID:$NB_GID $HOME

# Instala pacotes Python via Conda
ADD . /opt/install
RUN fix-permissions /opt/install

USER $NB_USER

RUN cd /opt/install && conda env update -n base --file environment.yml
