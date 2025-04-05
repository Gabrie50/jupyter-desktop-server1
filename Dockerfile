FROM jupyter/base-notebook:ubuntu-22.04

ENV DEBIAN_FRONTEND=noninteractive
ARG NB_USER
ARG NB_UID
ARG NB_GID

USER root

# Atualiza pacotes e instala dependências básicas
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    wget \
    cmake \
    meson \
    ninja-build \
    cargo \
    libxcb1-dev \
    libxcb-render0-dev \
    libxcb-xfixes0-dev \
    libxkbcommon-dev \
    libxkbcommon-x11-dev \
    libwayland-dev \
    libegl1-mesa-dev \
    libpixman-1-dev \
    libinput-dev \
    libx11-dev \
    libglvnd-dev \
    libxcb-composite0-dev \
    libxcb-ewmh-dev \
    libxcb-icccm4-dev \
    libxcb-cursor-dev \
    libxcb-xinerama0-dev \
    libxcb-xkb-dev \
    libx11-xcb-dev \
    xwayland \
    wayland-protocols \
    dbus-x11 \
    xauth \
    libgtk-3-dev \
    libgbm-dev \
    libvulkan-dev \
    libdrm-dev \
    libseat-dev \
    libsystemd-dev \
    libudev-dev \
    foot

# Atualiza o CMake para 3.30+
RUN apt-get remove -y cmake && \
    wget https://github.com/Kitware/CMake/releases/download/v3.30.0/cmake-3.30.0-linux-x86_64.sh && \
    chmod +x cmake-3.30.0-linux-x86_64.sh && \
    ./cmake-3.30.0-linux-x86_64.sh --skip-license --prefix=/usr/local && \
    rm cmake-3.30.0-linux-x86_64.sh

# Instala Hyprlang
RUN git clone --depth 1 --branch v0.3.2 https://github.com/hyprwm/hyprlang.git /opt/hyprlang && \
    cd /opt/hyprlang && \
    cmake -B build -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build -j$(nproc) && \
    cmake --install build && \
    rm -rf /opt/hyprlang

# Instala Hyprcursor
RUN git clone --depth 1 --branch v0.1.7 https://github.com/hyprwm/hyprcursor.git /opt/hyprcursor && \
    cd /opt/hyprcursor && \
    cmake -B build -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build -j$(nproc) && \
    cmake --install build && \
    rm -rf /opt/hyprcursor

# Compila e instala o Hyprland
RUN git clone --recursive -b v0.39.1 https://github.com/hyprwm/Hyprland.git /opt/Hyprland && \
    cd /opt/Hyprland && \
    cmake -B build -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build -j$(nproc) && \
    cmake --install build && \
    rm -rf /opt/Hyprland

# Compila e instala o foot terminal
RUN git clone https://codeberg.org/dnkl/foot.git /opt/foot && \
    cd /opt/foot && \
    meson setup build && \
    ninja -C build && \
    ninja -C build install && \
    rm -rf /opt/foot

# Compila e instala o Eww
RUN git clone https://github.com/elkowar/eww.git /opt/eww && \
    cd /opt/eww && \
    cargo build --release && \
    install -Dm755 target/release/eww /usr/local/bin/eww && \
    rm -rf /opt/eww

# Instala TurboVNC
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" -O turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    apt-get install -y ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    rm ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# Cria configuração do Eww com widget
RUN mkdir -p /home/jovyan/.config/eww/widgets && \
    echo '(defwidget hello-widget [] (box :orientation "vertical" (label :text "Olá, Jovyan!") (label :text "Hyprland está rodando!")))' > /home/jovyan/.config/eww/eww.yuck && \
    echo '#!/bin/sh\neww daemon\neww open hello-widget' > /home/jovyan/.config/eww/launch.sh && \
    chmod +x /home/jovyan/.config/eww/launch.sh

# Cria xstartup para TurboVNC com Hyprland e Eww
RUN mkdir -p /home/jovyan/.vnc && \
    echo '#!/bin/sh\n\
export XDG_SESSION_TYPE=wayland\n\
export XDG_CURRENT_DESKTOP=Hyprland\n\
export WLR_NO_HARDWARE_CURSORS=1\n\
export GDK_BACKEND=wayland\n\
export QT_QPA_PLATFORM=wayland\n\
exec dbus-launch Hyprland &\n\
sleep 3\n\
/home/jovyan/.config/eww/launch.sh' > /home/jovyan/.vnc/xstartup && \
    chmod +x /home/jovyan/.vnc/xstartup

# Corrige permissões
RUN chown -R $NB_UID:$NB_GID /home/jovyan

# Copia e instala ambiente Conda (se existir environment.yml)
ADD . /opt/install
RUN fix-permissions /opt/install

USER $NB_USER

RUN cd /opt/install && conda env update -n base --file environment.yml || true
