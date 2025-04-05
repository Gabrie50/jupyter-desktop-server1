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
    foot \
    wget

# Compila e instala Hyprland
RUN git clone https://github.com/hyprwm/Hyprland.git /opt/hyprland && \
    cd /opt/hyprland && \
    git submodule update --init --recursive && \
    mkdir -p build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release && \
    make -j$(nproc) && \
    make install

# Compila e instala Eww
RUN git clone https://github.com/elkowar/eww /opt/eww && \
    cd /opt/eww && \
    cargo build --release && \
    install -Dm755 target/release/eww /usr/local/bin/eww

# Instala TurboVNC
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" -O turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    apt-get install -y ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    rm ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# Cria arquivos de configuração do Eww
RUN mkdir -p /home/jovyan/.config/eww/widgets && \
    echo '(defwidget hello-widget [] (box :orientation "vertical" (label :text "Olá, Jovyan!") (label :text "Hyprland está rodando!")))' > /home/jovyan/.config/eww/eww.yuck && \
    echo '#!/bin/sh\neww daemon\neww open hello-widget' > /home/jovyan/.config/eww/launch.sh && \
    chmod +x /home/jovyan/.config/eww/launch.sh

# Cria o xstartup com Hyprland e Eww
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

# Copia arquivos locais (como environment.yml)
ADD . /opt/install
RUN fix-permissions /opt/install

USER $NB_USER

# Atualiza ambiente Conda
RUN cd /opt/install && \
    conda env update -n base --file environment.yml || true
    
