# Dockerfile com suporte a Hyprland + Jupyter + Eww + TurboVNC
FROM jupyter/base-notebook:ubuntu-22.04

ENV DEBIAN_FRONTEND=noninteractive
ARG NB_USER
ARG NB_UID
ARG NB_GID

USER root

# 1) Dependências de sistema e ferramentas de build
RUN apt-get update && apt-get install -y \
    software-properties-common \
    build-essential \
    cmake \
    ninja-build \
    pkg-config \
    git \
    wget \
    meson \
    cargo \
    libxcb1-dev libxcb-render0-dev libxcb-xfixes0-dev \
    libxkbcommon-dev libxkbcommon-x11-dev \
    libwayland-dev libegl1-mesa-dev libpixman-1-dev libinput-dev \
    libx11-dev libglvnd-dev libxcb-composite0-dev libxcb-ewmh-dev \
    libxcb-icccm4-dev libxcb-cursor-dev libxcb-xinerama0-dev \
    libxcb-xkb-dev libx11-xcb-dev xwayland wayland-protocols \
    dbus-x11 xauth libgtk-3-dev \
    libzip-dev librsvg2-dev libcairo2-dev libfmt-dev nlohmann-json3-dev \
    curl unzip ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2) GCC‑13/G++‑13 para suporte a std::format
RUN add-apt-repository ppa:ubuntu-toolchain-r/test -y && \
    apt-get update && \
    apt-get install -y gcc-13 g++-13 libstdc++-13-dev && \
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-13 100 && \
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-13 100 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 3) CMake 3.30+
RUN apt-get remove -y cmake && \
    wget -q https://github.com/Kitware/CMake/releases/download/v3.30.0/cmake-3.30.0-linux-x86_64.sh && \
    chmod +x cmake-3.30.0-linux-x86_64.sh && \
    ./cmake-3.30.0-linux-x86_64.sh --skip-license --prefix=/usr/local && \
    rm cmake-3.30.0-linux-x86_64.sh

# 4) hyprutils
RUN git clone --depth 1 --branch v0.1.1 https://github.com/hyprwm/hyprutils.git /opt/hyprutils && \
    cd /opt/hyprutils && \
    cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build && \
    cmake --install build && \
    rm -rf /opt/hyprutils

# 5) tomlplusplus
RUN git clone --depth 1 --branch v3.2.0 https://github.com/marzer/tomlplusplus.git /opt/tomlplusplus && \
    cd /opt/tomlplusplus && \
    cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local && \
    cmake --build build && \
    cmake --install build && \
    printf 'prefix=/usr/local\nexec_prefix=${prefix}\nlibdir=${exec_prefix}/lib\nincludedir=${prefix}/include\n\nName: tomlplusplus\nDescription: Header-only TOML parser library\nVersion: 3.2.0\nRequires:\nLibs:\nCflags: -I${includedir}\n' \
        > /usr/local/lib/pkgconfig/tomlplusplus.pc && \
    rm -rf /opt/tomlplusplus

# 6) hyprlang
RUN git clone --depth 1 --branch v0.4.2 https://github.com/hyprwm/hyprlang.git /opt/hyprlang && \
    cd /opt/hyprlang && \
    cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build && \
    cmake --install build && \
    rm -rf /opt/hyprlang

# 7) hyprcursor (CORRIGIDO com include do toml++)
RUN git clone --depth 1 https://github.com/hyprwm/hyprcursor.git /opt/hyprcursor && \
    sed -i '/add_subdirectory(hyprcursor-util)/d' /opt/hyprcursor/CMakeLists.txt && \
    cmake -S /opt/hyprcursor -B /opt/hyprcursor/build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_FLAGS="-I/usr/local/include" \
        -DHYPRCURSOR_BUILD_TESTS=OFF \
        -DHYPRCURSOR_BUILD_UTIL=OFF && \
    cmake --build /opt/hyprcursor/build && \
    cmake --install /opt/hyprcursor/build && \
    rm -rf /opt/hyprcursor

# 8) Terminal foot
RUN git clone https://codeberg.org/dnkl/foot.git /opt/foot && \
    cd /opt/foot && \
    meson setup build && \
    ninja -C build && \
    ninja -C build install && \
    rm -rf /opt/foot

# 9) Eww
RUN git clone https://github.com/elkowar/eww.git /opt/eww && \
    cd /opt/eww && \
    cargo build --release && \
    install -Dm755 target/release/eww /usr/local/bin/eww && \
    rm -rf /opt/eww

# 10) TurboVNC
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" \
        -O turbovnc.deb && \
    apt-get install -y ./turbovnc.deb && \
    rm turbovnc.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# 11) Widget Eww de exemplo
RUN mkdir -p /home/jovyan/.config/eww/widgets && \
    echo '(defwidget hello-widget [] (box :orientation "vertical" (label :text "Olá, Jovyan!") (label :text "Hyprland está rodando!")))' \
        > /home/jovyan/.config/eww/eww.yuck && \
    echo '#!/bin/sh\n\
eww daemon\n\
eww open hello-widget' \
        > /home/jovyan/.config/eww/launch.sh && \
    chmod +x /home/jovyan/.config/eww/launch.sh

# 12) xstartup do TurboVNC com Hyprland + Eww
RUN mkdir -p /home/jovyan/.vnc && \
    printf '#!/bin/sh\n\
export XDG_SESSION_TYPE=wayland\n\
export XDG_CURRENT_DESKTOP=Hyprland\n\
export WLR_NO_HARDWARE_CURSORS=1\n\
export GDK_BACKEND=wayland\n\
export QT_QPA_PLATFORM=wayland\n\
exec dbus-launch Hyprland &\n\
sleep 3\n\
/home/jovyan/.config/eww/launch.sh\n' \
        > /home/jovyan/.vnc/xstartup && \
    chmod +x /home/jovyan/.vnc/xstartup

# 13) Permissões e Conda
RUN chown -R $NB_UID:$NB_GID /home/jovyan
ADD . /opt/install
RUN fix-permissions /opt/install

USER $NB_USER
RUN cd /opt/install && conda env update -n base --file environment.yml || true

ENV PATH="/home/jovyan/.local/bin:$PATH"
