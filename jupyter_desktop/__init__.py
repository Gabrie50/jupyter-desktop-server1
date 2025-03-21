import os
import shlex
from shutil import which
import tempfile
import platform

HERE = os.path.dirname(os.path.abspath(__file__))


def detect_device():
    """Detecta o tipo de dispositivo baseado na resolução da tela."""
    try:
        import subprocess
        output = subprocess.check_output("xdpyinfo | grep dimensions", shell=True).decode()
        resolution = output.split()[1]
        width, height = map(int, resolution.split('x'))
    except Exception as e:
        print(f"Falha ao detectar resolução: {e}")
        width, height = 1920, 1080  # Resolução padrão

    # Classificação por resolução
    if width <= 720:
        return "mobile", "720x1280"
    elif width <= 1280:
        return "tablet", "1280x800"
    elif width <= 1920:
        return "desktop", "1920x1080"
    else:
        return "tv", "3840x2160"


def setup_desktop():
    # Define o tipo de dispositivo e a resolução correspondente
    device_type, screen_resolution = detect_device()
    print(f"Detectado: {device_type} - Resolução: {screen_resolution}")

    # Cria diretório seguro temporário para o socket
    sockets_dir = tempfile.mkdtemp()
    sockets_path = os.path.join(sockets_dir, 'vnc-socket')
    vncserver = which('vncserver')

    if vncserver:
        vnc_args = [
            vncserver,
        ]
        socket_args = []
    else:
        # Usa o TigerVNC incluso se não achar outro
        vnc_args = [
            os.path.join(HERE, 'share/tigervnc/bin/vncserver'),
            '-rfbunixpath', sockets_path,
        ]
        socket_args = [
            '--unix-target', sockets_path
        ]

    # Define o comando do servidor VNC com a resolução específica do dispositivo
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
    
