FROM jupyter/base-notebook:python-3.10

USER root

# Variáveis para compilação
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/root/.cargo/bin:${PATH}"

# Atualiza pacotes e instala dependências
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
    curl \
    build-essential \
    libegl-dev \
    libwayland-dev \
    libdrm-dev \
    libxkbcommon-dev \
    libpixman-1-dev \
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
    libxcb-util0-dev \
    libgtk-3-dev \
    ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Instala Rust (necessário para compilar o eww)
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y

# Instala foot
RUN git clone https://codeberg.org/dnkl/foot.git && \
    cd foot && \
    meson build && \
    ninja -C build && \
    ninja -C build install && \
    cd .. && rm -rf foot

# Instala eww
RUN git clone https://github.com/elkowar/eww.git && \
    cd eww && \
    cargo build --release && \
    install -Dm755 target/release/eww /usr/local/bin/eww && \
    cd .. && rm -rf eww

USER ${NB_UID}


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
    
