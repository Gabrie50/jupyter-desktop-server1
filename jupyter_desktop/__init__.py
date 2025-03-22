import os
import shlex
from shutil import which
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

def setup_desktop():
    # Detecta a resolução da tela automaticamente ou usa padrão
    width = os.getenv("SCREEN_WIDTH", "1280")
    height = os.getenv("SCREEN_HEIGHT", "720")
    resolution = f"{width}x{height}"

    # Cria um diretório temporário para os sockets
    sockets_dir = tempfile.mkdtemp()
    sockets_path = os.path.join(sockets_dir, 'vnc-socket')

    # Verifica se o vncserver está disponível
    vncserver = which('vncserver')
    if vncserver:
        vnc_args = [vncserver]
        socket_args = []
    else:
        # Usa o TigerVNC embutido se não encontrar o comando
        vnc_args = [
            os.path.join(HERE, 'share/tigervnc/bin/vncserver'),
            '-rfbunixpath', sockets_path,
        ]
        socket_args = ['--unix-target', sockets_path]

    # Monta o comando do VNC com resolução
    vnc_command = ' '.join(shlex.quote(p) for p in (vnc_args + [
        '-verbose',
        '-xstartup', os.path.join(HERE, 'share/xstartup'),
        '-geometry', resolution,
        '-SecurityTypes', 'None',
        '-fg',
        ':1',
    ]))

    # Retorna a configuração completa do servidor
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

# Teste de execução
if __name__ == "__main__":
    config = setup_desktop()
    print("Configuração gerada com sucesso!")
    print(config)
    
