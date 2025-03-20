import os
import shlex
from shutil import which
import tempfile

# Define o diretório atual do script
HERE = os.path.dirname(os.path.abspath(__file__))

def setup_desktop(geometry='1680x400'):
    """
    Configura o ambiente de desktop para o VNC server.
    
    Args:
        geometry (str): Resolução da tela no formato 'LARGURAxALTURA'. Padrão é '1680x1050'.
    
    Returns:
        dict: Configurações para iniciar o servidor VNC e o WebSockify.
    """
    # Cria um diretório temporário seguro para os sockets
    sockets_dir = tempfile.mkdtemp()
    sockets_path = os.path.join(sockets_dir, 'vnc-socket')

    # Verifica se o vncserver está instalado no sistema
    vncserver = which('vncserver')

    if vncserver:
        # Usa o vncserver do sistema, se disponível
        vnc_args = [vncserver]
        socket_args = []
    else:
        # Usa o TigerVNC empacotado (caso o vncserver não esteja instalado)
        vnc_args = [
            os.path.join(HERE, 'share/tigervnc/bin/vncserver'),
            '-rfbunixpath', sockets_path,
        ]
        socket_args = [
            '--unix-target', sockets_path
        ]

    # Monta o comando para iniciar o VNC server
    vnc_command = ' '.join(shlex.quote(p) for p in (vnc_args + [
        '-verbose',
        '-xstartup', os.path.join(HERE, 'share/xstartup'),
        '-geometry', geometry,  # Usa a geometria fornecida pelo usuário
        '-SecurityTypes', 'None',
        '-fg',
        ':1',
    ]))

    # Retorna a configuração completa para o servidor VNC e WebSockify
    return {
        'command': [
            'websockify', '-v',
            '--web', os.path.join(HERE, 'share/web/noVNC-1.6.0'),
            '--heartbeat', '30',
            '5901',
        ] + socket_args + [
            '--',
            '/bin/sh', '-c',
            f'cd {os.getcwd()} && {vnc_command}'
        ],
        'port': 5901,  # Porta padrão do VNC
        'timeout': 30,  # Tempo limite de conexão
        'mappath': {'/': '/vnc.html'},  # Mapeamento do caminho do noVNC
        'new_browser_window': True  # Abre em uma nova janela do navegador
    }
