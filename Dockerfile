FROM jupyter/base-notebook:python-3.7.6

USER root

# Atualiza os pacotes e instala o KDE completo e dependências
RUN apt-get -y update && apt-get install -y \
    dbus-x11 \
    firefox \
    kde-standard \  # mais completo que kde-plasma-desktop
    kwin-x11 \
    sddm \
    xorg \
    x11-xserver-utils \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Instala o TurboVNC
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" \
    -O turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    apt-get install -y -q ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    rm ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# Corrige permissões para o usuário padrão do Jupyter
RUN chown -R $NB_UID:$NB_GID $HOME

# Copia os arquivos de instalação
ADD . /opt/install
RUN fix-permissions /opt/install

# Instala ambiente Conda personalizado
USER $NB_USER
RUN cd /opt/install && \
    conda env update -n base --file environment.yml
    
