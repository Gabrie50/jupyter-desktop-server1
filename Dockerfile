FROM jupyter/base-notebook:python-3.7.6

USER root

RUN apt-get -y update && apt-get install -y \
    dbus-x11 \
    firefox \
    xorg \
    wayland-protocols \
    foot \
    alacritty \
    waybar \
    eww \
    hyprland \
    wget

# TurboVNC (igual)
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" -O turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    apt-get install -y -q ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    rm ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

RUN chown -R $NB_UID:$NB_GID $HOME

ADD . /opt/install
RUN fix-permissions /opt/install

USER $NB_USER

RUN cd /opt/install && \
    conda env update -n base --file environment.yml
    
