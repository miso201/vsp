import apt
import pathlib
import shutil
import subprocess
import secrets
import IPython.utils.io
import ipywidgets

class _NoteProgress(apt.progress.base.InstallProgress, apt.progress.base.AcquireProgress, apt.progress.base.OpProgress):
    def __init__(self):
        apt.progress.base.InstallProgress.__init__(self)
        self._label = ipywidgets.Label()
        display(self._label)
        self._float_progress = ipywidgets.FloatProgress(min=0.0, max=1.0, layout={'border': '1px solid #118800'})
        display(self._float_progress)

    def close(self):
        self._float_progress.close()
        self._label.close()

    def fetch(self, item):
        self._label.value = "fetch: " + item.shortdesc

    def pulse(self, owner):
        self._float_progress.value = self.current_items / self.total_items
        return True

    def status_change(self, pkg, percent, status):
        self._label.value = "%s: %s" % (pkg, status)
        self._float_progress.value = percent / 100.0

    def update(self, percent=None):
        self._float_progress.value = self.percent / 100.0
        self._label.value = self.op + ": " + self.subop

    def done(self, item=None):
        pass

class _MyApt:
    def __init__(self):
        self._progress = _NoteProgress()
        self._cache = apt.Cache(self._progress)

    def close(self):
        self._cache.close()
        self._cache = None
        self._progress.close()
        self._progress = None

    def update_upgrade(self):
        self._cache.update()
        self._cache.open(None)
        self._cache.upgrade()

    def commit(self):
        self._cache.commit(self._progress, self._progress)
        self._cache.clear()

    def installPkg(self, *args):
        for name in args:
            pkg = self._cache[name]
            if pkg.is_installed:
                print(f"{name} is already installed")
            else:
                print(f"Install {name}")
                pkg.mark_install()

def _set_public_key(user, public_key):
    if public_key is not None:
        home_dir = pathlib.Path("/root" if user == "root" else "/home/" + user)
        ssh_dir = home_dir / ".ssh"
        ssh_dir.mkdir(mode=0o700, exist_ok=True)
        auth_keys_file = ssh_dir / "authorized_keys"
        auth_keys_file.write_text(public_key)
        auth_keys_file.chmod(0o600)
        if user != "root":
            shutil.chown(ssh_dir, user)
            shutil.chown(auth_keys_file, user)

def _setupSSHD(public_key, mount_gdrive_to=None, mount_gdrive_from=None, is_VNC=False):
    my_apt = _MyApt()
    my_apt.update_upgrade()
    my_apt.commit()

    subprocess.run(["unminimize"], input="y\n", check=True, universal_newlines=True)

    my_apt.installPkg("openssh-server")
    if mount_gdrive_to:
        my_apt.installPkg("bindfs")

    my_apt.commit()
    my_apt.close()

    # Reset host keys
    for i in pathlib.Path("/etc/ssh").glob("ssh_host_*_key"):
        i.unlink()
    subprocess.run(["ssh-keygen", "-A"], check=True)

    # Prevent ssh session disconnection
    with open("/etc/ssh/sshd_config", "a") as f:
        f.write("\n\n# Options added by remocolab\n")
        f.write("ClientAliveInterval 120\n")
        if public_key is not None:
            f.write("PasswordAuthentication no\n")

    root_password = secrets.token_urlsafe()
    user_password = secrets.token_urlsafe()
    user_name = "colab"

    subprocess.run(["useradd", "-s", "/bin/bash", "-m", user_name])
    subprocess.run(["adduser", user_name, "sudo"], check=True)
    subprocess.run(["chpasswd"], input=f"root:{root_password}", universal_newlines=True)
    subprocess.run(["chpasswd"], input=f"{user_name}:{user_password}", universal_newlines=True)
    subprocess.run(["service", "ssh", "restart"])
    _set_public_key(user_name, public_key)

    if mount_gdrive_to:
        user_gdrive_dir = pathlib.Path("/home") / user_name / mount_gdrive_to
        pathlib.Path(user_gdrive_dir).mkdir(parents=True)
        gdrive_root = pathlib.Path("/content/drive")
        target_gdrive_dir = (gdrive_root / mount_gdrive_from) if mount_gdrive_from else gdrive_root
        subprocess.run(["bindfs", "-u", user_name, "-g", user_name, target_gdrive_dir, user_gdrive_dir], check=True)

    print("\n" + "*" * 24)
    print("SSH server is running.")
    print("Connect using the following command:")
    print(f"ssh {user_name}@<YOUR_COLAB_IP_ADDRESS>")  # Replace <YOUR_COLAB_IP_ADDRESS> with the actual IP

    if is_VNC:
        subprocess.run(["apt-get", "install", "-y", "xfce4", "xfce4-goodies", "tightvncserver", "x11vnc"], check=True)
        subprocess.run(["vncserver"], input=f"{user_password}\n", check=True)

        print("VNC server is running.")
        print("Connect to your VNC server with the following command:")
        print(f"vncviewer <YOUR_COLAB_IP_ADDRESS>:1")  # Replace <YOUR_COLAB_IP_ADDRESS> with the actual IP

        print("\nTo stop the VNC server, use:")
        print("vncserver -kill :1")

    print("*" * 24 + "\n")

# Example Usage
setup_public_key = "your_public_key_here"  # Replace with your public SSH key
mount_gdrive_to = None  # Or specify a directory name to mount
mount_gdrive_from = None  # Optional path in Google Drive to mount
is_VNC = False  # Set to True if you want to enable VNC

# Call to set up the SSH server
_setupSSHD(setup_public_key, mount_gdrive_to, mount_gdrive_from, is_VNC)
