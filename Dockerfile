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

# Compila e instala Hyprland
RUN git clone --recursive https://github.com/hyprwm/Hyprland.git /opt/Hyprland && \
    cd /opt/Hyprland && \
    cmake -B build -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build -j$(nproc) && \
    cmake --install build && \
    rm -rf /opt/Hyprland

# Compila e instala foot terminal
RUN git clone https://codeberg.org/dnkl/foot.git /opt/foot && \
    cd /opt/foot && \
    meson setup build && \
    ninja -C build && \
    ninja -C build install && \
    rm -rf /opt/foot

# Compila e instala Eww com widgets
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

# Configuração do Eww com widget
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
RUN chown -R $NB_UID:$NB_GID /home/jovyan && \
    chown -R $NB_UID:$NB_GID $HOME

# Instala Conda environment
ADD . /opt/install
RUN fix-permissions /opt/install

USER $NB_USER

# Atualiza ambiente Conda
RUN cd /opt/install && \
    conda env update -n base --file environment.yml || true
    
