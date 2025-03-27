FROM jupyter/base-notebook:python-3.7.6

USER root

# Atualiza pacotes e instala os necessários para um ambiente gráfico com i3
RUN apt-get update && \
    apt-get install -y \
        dbus-x11 \
        xorg \
        x11-xserver-utils \
        xinit \
        wget \
        i3 \
        chromium-browser \
        nano \
    --no-install-recommends && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Instala o TurboVNC
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" \
        -O turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    apt-get install -y ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    rm ./turbovnc_${TURBOVNC_VERSION}_amd64.deb && \
    ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# Corrige permissões do diretório do usuário
RUN usermod -aG sudo jovyan && \
    chown -R jovyan:jovyan /home/jovyan

# Cria a configuração do i3 diretamente (para não precisar configurar na primeira inicialização)
RUN mkdir -p /home/jovyan/.config/i3 && \
    echo "set \$mod Mod4" > /home/jovyan/.config/i3/config && \
    echo "bindsym \$mod+Return exec i3-sensible-terminal" >> /home/jovyan/.config/i3/config && \
    echo "bindsym \$mod+Shift+q kill" >> /home/jovyan/.config/i3/config && \
    echo "bindsym \$mod+d exec dmenu_run" >> /home/jovyan/.config/i3/config && \
    echo "exec --no-startup-id i3" >> /home/jovyan/.config/i3/config && \
    chown -R jovyan:jovyan /home/jovyan/.config

# Adiciona arquivos extras, se necessário
ADD . /opt/install
RUN fix-permissions /opt/install

USER jovyan
# Atualiza o ambiente Conda (se necessário)
RUN cd /opt/install && conda env update -n base --file environment.yml || true

USER root

# Cria o arquivo xstartup no local correto
RUN mkdir -p /opt/jupyter_desktop/share/ && \
    echo '#!/bin/sh' > /opt/jupyter_desktop/share/xstartup && \
    echo 'export XDG_SESSION_TYPE=x11' >> /opt/jupyter_desktop/share/xstartup && \
    echo 'export DISPLAY=:1' >> /opt/jupyter_desktop/share/xstartup && \
    echo 'exec dbus-launch i3' >> /opt/jupyter_desktop/share/xstartup && \
    chmod +x /opt/jupyter_desktop/share/xstartup

# Comando de entrada: inicia o xstartup
CMD ["/opt/jupyter_desktop/share/xstartup"]
