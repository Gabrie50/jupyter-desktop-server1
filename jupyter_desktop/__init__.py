import os
import shlex
from shutil import which
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

def setup_desktop():
    # Cria diretório seguro temporário para o socket
    sockets_dir = tempfile.mkdtemp()
    sockets_path = os.path.join(sockets_dir, 'vnc-socket')
    vncserver = which('vncserver')

    if vncserver:
        vnc_args = [vncserver]
        socket_args = []
    else:
        # Usa TigerVNC incluído
        vnc_args = [
            os.path.join(HERE, 'share/tigervnc/bin/vncserver'),
            '-rfbunixpath', sockets_path,
        ]
        socket_args = ['--unix-target', sockets_path]

    # Usa uma resolução inicial e ativa a redimensionável
    vnc_command = ' '.join(shlex.quote(p) for p in (vnc_args + [
        '-verbose',
        '-xstartup', os.path.join(HERE, 'share/xstartup'),
        '-geometry', '1600x900',
        '-localhost', 'yes',
        '-SecurityTypes', 'None',
        '-fg',
        '-randr', '1600x900,1920x1080,2560x1440,3840x2160',
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
        'mappath': {'/': '/vnc.html?resize=remote'},
        'new_browser_window': True
    }
    
