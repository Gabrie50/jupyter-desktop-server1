import os
import shlex
from shutil import which
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

def setup_desktop():
    # Cria um diretório temporário seguro para os sockets
    sockets_dir = tempfile.mkdtemp()
    sockets_path = os.path.join(sockets_dir, 'vnc-socket')
    vncserver = which('vncserver')

    # Detecta a resolução da tela usando o comando "xdpyinfo"
    try:
        import subprocess
        output = subprocess.check_output("xdpyinfo | grep dimensions", shell=True).decode()
        screen_resolution = output.split()[1]
    except Exception as e:
        print(f"Falha ao detectar a resolução da tela: {e}")
        screen_resolution = "1920x1080"  # Resolução padrão de fallback

    if vncserver:
        vnc_args = [
            vncserver,
        ]
        socket_args = []
    else:
        # Usa o TigerVNC incluso, se não encontrar outro VNC
        vnc_args = [
            os.path.join(HERE, 'share/tigervnc/bin/vncserver'),
            '-rfbunixpath', sockets_path,
        ]
        socket_args = [
            '--unix-target', sockets_path
        ]

    # Define o comando do servidor VNC com a resolução dinâmica
    vnc_command = ' '.join(shlex.quote(p) for p in (vnc_args + [
        '-verbose',
        '-xstartup', os.path.join(HERE, 'share/xstartup'),
        '-geometry', screen_resolution,
        '-SecurityTypes', 'None',
        '-fg',
        ':1',
    ]))

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
        'port': 5901,
        'timeout': 30,
        'mappath': {'/': '/vnc.html'},
        'new_browser_window': True
        }
    
