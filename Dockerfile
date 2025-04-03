FROM jupyter/base-notebook:python-3.7.6

USER root

# Atualiza os pacotes e instala dependências necessárias
RUN apt-get -y update && apt-get install -y \
    dbus-x11 \
    firefox \
    kde-plasma-desktop \
    kwin-x11 \
    sddm \
    xorg \
    x11-xserver-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Instala o TurboVNC sem tentar remover o light-locker
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" -O turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    apt-get install -y -q ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    rm ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# Corrige permissões para o usuário do notebook
RUN chown -R $NB_UID:$NB_GID $HOME

ADD . /opt/install
RUN fix-permissions /opt/install

USER $NB_USER
RUN cd /opt/install && \
    conda env update -n base --file environment.yml
    
